import SwiftUI

struct WorkspaceHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing:14) {
            Image(systemName:symbol).font(.system(size:23,weight:.medium)).foregroundStyle(.indigo)
                .frame(width:48,height:48).background(.indigo.opacity(0.09),in:RoundedRectangle(cornerRadius:13))
            VStack(alignment:.leading,spacing:5) {
                Text(title).font(.system(size:26,weight:.bold)).tracking(-0.5)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
struct Surface<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).background(.background,in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(.primary.opacity(0.07),lineWidth:1))
    }
}
struct MetricPill: View {
    var title: String
    var symbol: String
    var body: some View {
        Label(title,systemImage:symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal,10).padding(.vertical,6).background(.primary.opacity(0.04),in:Capsule())
    }
}
struct FieldCaption: View {
    var title: String
    var body: some View { Text(title).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary) }
}
