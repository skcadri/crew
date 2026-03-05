import SwiftUI

/// A single row in the sidebar representing a cloned repository.
struct RepoRow: View {
    let repo: Repository

    var body: some View {
        Label {
            Text(repo.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
        }
        .help(repo.url)
    }
}

#Preview {
    List {
        RepoRow(repo: Repository(
            name: "my-app",
            url: "https://github.com/user/my-app.git",
            localPath: "/tmp/my-app"
        ))
    }
    .frame(width: 240, height: 120)
}
