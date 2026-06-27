import Foundation

class AerospaceSpacesProvider {
    func getSpacesWithWindows() -> [AeroSpace]? {
        // Calls run over the AeroSpace socket (AerospaceClient), so there is no
        // process-spawn cost and the server serializes clients anyway —
        // sequential is as fast as parallel here and far simpler. fetchSpaces
        // carries `workspace-is-focused` inline, so the focused space falls out
        // of that call (no separate focused-space request).
        guard let spaces = fetchSpaces(), let windows = fetchWindows() else {
            return nil
        }
        let focusedWindow = fetchFocusedWindow()

        // isFocused is set during decode from `workspace-is-focused`.
        let focusedSpaceID = spaces.first(where: { $0.isFocused })?.id
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) }
        )
        for window in windows {
            var mutableWindow = window
            if let focused = focusedWindow, window.id == focused.id {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let focusedSpaceID {
                // Windows with no workspace string belong to the focused space.
                if var space = spaceDict[focusedSpaceID] {
                    space.windows.append(mutableWindow)
                    spaceDict[focusedSpaceID] = space
                }
            }
        }
        let resultSpaces = Array(spaceDict.values)
        return resultSpaces.filter { !$0.windows.isEmpty || $0.isFocused }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) {
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        AerospaceClient.run(arguments)
    }

    private func fetchSpaces() -> [AeroSpace]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--all", "--json", "--format",
                "%{workspace} %{workspace-is-focused}",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data)
        } catch {
            print("Decode spaces error: \(error)")
            return nil
        }
    }

    private func fetchWindows() -> [AeroWindow]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{window-title} %{workspace}",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data)
        } catch {
            print("Decode windows error: \(error)")
            return nil
        }
    }

    private func fetchFocusedWindow() -> AeroWindow? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data).first
        } catch {
            print("Decode focused window error: \(error)")
            return nil
        }
    }
}
