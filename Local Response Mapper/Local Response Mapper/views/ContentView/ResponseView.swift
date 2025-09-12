import SwiftUI
import CodeEditor
import AVKit

struct ResponseView: View {

    private let item: URLTaskObject
    private let theme: CodeEditor.ThemeName
    @State private var player: AVPlayer?

    init(
        item: URLTaskObject,
        theme: CodeEditor.ThemeName
    ) {
        self.item = item
        self.theme = theme
    }

    var body: some View {
        content
            .onAppear {
                if item.contentType == .video, let url = item.fileURL {
                    player = AVPlayer(url: url)
                }
            }
    }

    @ViewBuilder
    var content: some View {
        if item.statusCode != 0 {
            VStack {
                Spacer()
                if let url = item.fileURL {
                    let imageSize = item.image != nil ? " (\(Int(item.image?.1.width ?? 0))x\(Int(item.image?.1.height ?? 0)))" : ""
                    HStack(alignment: .center) {
                        Text("\(url.path)\(imageSize)")
                            .textSelection(.enabled)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.accentColor)
                        Button("", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .offset(y: -2)
                        .buttonStyle(.borderless)
                    }
                    .padding(4)
                    .background {
                        Color.gray.opacity(0.2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                switch item.contentType {
                case .text:
                    MyTextEditor(
                        source: .constant(item.responseString),
                        language: .json,
                        theme: theme,
                        flags: [.selectable]
                    )
                    .id(item.id)
                case .image:
                    if let image = item.image {
                        FittingImageView(
                            image: image.0,
                            originalSize: image.1
                        )
                    } else {
                        Text("Bad image data")
                    }
                case .video:
                    if let player = player {
                        VideoPlayer(player: player)
                    } else {
                        Text("Bad video data")
                    }
                default:
                    Text("Unsupported content type")
                    Text(item.responseString)
                }
                Spacer()
            }
        } else {
            ProgressView()
        }
    }
}

#Preview {
    let text = {
        let item: URLTaskObject = URLTaskObject(
            taskId: "text1"
        )
        item.responseString = "abc"
        item.resHeaders["Content-Type"] = "application/json"
        return item
    }()

    let image = {
        let id = "image1"
        let item: URLTaskObject = URLTaskObject(
            taskId: id
        )
        item.updateFrom(
            task: URLTaskModelEnd(
                taskId: id,
                resString: nil,
                resStringB64: "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAApgAAAKYB3X3/OAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAANCSURBVEiJtZZPbBtFFMZ/M7ubXdtdb1xSFyeilBapySVU8h8OoFaooFSqiihIVIpQBKci6KEg9Q6H9kovIHoCIVQJJCKE1ENFjnAgcaSGC6rEnxBwA04Tx43t2FnvDAfjkNibxgHxnWb2e/u992bee7tCa00YFsffekFY+nUzFtjW0LrvjRXrCDIAaPLlW0nHL0SsZtVoaF98mLrx3pdhOqLtYPHChahZcYYO7KvPFxvRl5XPp1sN3adWiD1ZAqD6XYK1b/dvE5IWryTt2udLFedwc1+9kLp+vbbpoDh+6TklxBeAi9TL0taeWpdmZzQDry0AcO+jQ12RyohqqoYoo8RDwJrU+qXkjWtfi8Xxt58BdQuwQs9qC/afLwCw8tnQbqYAPsgxE1S6F3EAIXux2oQFKm0ihMsOF71dHYx+f3NND68ghCu1YIoePPQN1pGRABkJ6Bus96CutRZMydTl+TvuiRW1m3n0eDl0vRPcEysqdXn+jsQPsrHMquGeXEaY4Yk4wxWcY5V/9scqOMOVUFthatyTy8QyqwZ+kDURKoMWxNKr2EeqVKcTNOajqKoBgOE28U4tdQl5p5bwCw7BWquaZSzAPlwjlithJtp3pTImSqQRrb2Z8PHGigD4RZuNX6JYj6wj7O4TFLbCO/Mn/m8R+h6rYSUb3ekokRY6f/YukArN979jcW+V/S8g0eT/N3VN3kTqWbQ428m9/8k0P/1aIhF36PccEl6EhOcAUCrXKZXXWS3XKd2vc/TRBG9O5ELC17MmWubD2nKhUKZa26Ba2+D3P+4/MNCFwg59oWVeYhkzgN/JDR8deKBoD7Y+ljEjGZ0sosXVTvbc6RHirr2reNy1OXd6pJsQ+gqjk8VWFYmHrwBzW/n+uMPFiRwHB2I7ih8ciHFxIkd/3Omk5tCDV1t+2nNu5sxxpDFNx+huNhVT3/zMDz8usXC3ddaHBj1GHj/As08fwTS7Kt1HBTmyN29vdwAw+/wbwLVOJ3uAD1wi/dUH7Qei66PfyuRj4Ik9is+hglfbkbfR3cnZm7chlUWLdwmprtCohX4HUtlOcQjLYCu+fzGJH2QRKvP3UNz8bWk1qMxjGTOMThZ3kvgLI5AzFfo379UAAAAASUVORK5CYII=",
                resHeaders: ["Content-Type": "image/png"],
                statusCode: 200,
                error: nil,
                bundleID: "bundle.id",
                mimeType: "image/png"
            )
        )
        return item
    }()

    let video = {
        let id = "video1"
        let item: URLTaskObject = URLTaskObject(
            taskId: id
        )
        item.updateFrom(
            task: URLTaskModelEnd(
                taskId: id,
                resString: nil,
                resStringB64: "AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAA19tZGF0AAACrgYF//+q3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NCByMzE5MSA0NjEzYWMzIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNCAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTIgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTEwIHNjZW5lY3V0PTQwIGludHJhX3JlZnJlc2g9MCByY19sb29rYWhlYWQ9NDAgcmM9Y3JmIG1idHJlZT0xIGNyZj0yMy4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0xLjQwIGFxPTE6MS4wMACAAAAAIWWIhAAR//73iB8yy2+catdyEeesVP1GIxltc+dmuhineQAAAApBmiRsQQ/+qlfeAAAACEGeQniHfwW9AAAACAGeYXRDfwd8AAAACAGeY2pDfwd9AAAAEEGaaEmoQWiZTAh3//6pnTUAAAAKQZ6GRREsO/8FvQAAAAgBnqV0Q38HfQAAAAgBnqdqQ38HfAAAABBBmqlJqEFsmUwIb//+p4+IAAADom1vb3YAAABsbXZoZAAAAAAAAAAAAAAAAAAAA+gAAAPoAAEAAAEAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAALNdHJhawAAAFx0a2hkAAAAAwAAAAAAAAAAAAAAAQAAAAAAAAPoAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAAAyAAAAMgAAAAAAJGVkdHMAAAAcZWxzdAAAAAAAAAABAAAD6AAACAAAAQAAAAACRW1kaWEAAAAgbWRoZAAAAAAAAAAAAAAAAAAAKAAAACgAVcQAAAAAAC1oZGxyAAAAAAAAAAB2aWRlAAAAAAAAAAAAAAAAVmlkZW9IYW5kbGVyAAAAAfBtaW5mAAAAFHZtaGQAAAABAAAAAAAAAAAAAAAkZGluZgAAABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAAGwc3RibAAAALBzdHNkAAAAAAAAAAEAAACgYXZjMQAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAyADIASAAAAEgAAAAAAAAAARRMYXZjNjEuMy4xMDAgbGlieDI2NAAAAAAAAAAAAAAAABj//wAAADZhdmNDAWQACv/hABlnZAAKrNlEJ4iIhAAAAwAEAAADAFA8SJZYAQAGaOvjyyLA/fj4AAAAABRidHJ0AAAAAAAAGrgAABq4AAAAGHN0dHMAAAAAAAAAAQAAAAoAAAQAAAAAFHN0c3MAAAAAAAAAAQAAAAEAAABgY3R0cwAAAAAAAAAKAAAAAQAACAAAAAABAAAUAAAAAAEAAAgAAAAAAQAAAAAAAAABAAAEAAAAAAEAABQAAAAAAQAACAAAAAABAAAAAAAAAAEAAAQAAAAAAQAACAAAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAoAAAABAAAAPHN0c3oAAAAAAAAAAAAAAAoAAALXAAAADgAAAAwAAAAMAAAADAAAABQAAAAOAAAADAAAAAwAAAAUAAAAFHN0Y28AAAAAAAAAAQAAADAAAABhdWR0YQAAAFltZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYxLjEuMTAw=",
                resHeaders: ["Content-Type": "video/mp4"],
                statusCode: 200,
                error: nil,
                bundleID: "bundle.id",
                mimeType: "video/mp4"
            )
        )
        return item
    }()

    Group {
        ResponseView(item: text, theme: .default)
            .frame(width: 400, height: 100)

        ResponseView(item: image, theme: .default)
            .frame(width: 400, height: 100)

        ResponseView(item: video, theme: .default)
            .frame(width: 400, height: 200)
    }
}
