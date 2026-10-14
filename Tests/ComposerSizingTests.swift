@main
struct ComposerSizingTests {
    static func main() {
        precondition(UMComposerSizing.height(contentHeight: 0, lineHeight: 20, maxLines: 8) == 20)
        print("PASS: empty draft is one line")
        precondition(UMComposerSizing.height(contentHeight: 60, lineHeight: 20, maxLines: 8) == 60)
        print("PASS: wrapped draft grows")
        precondition(UMComposerSizing.height(contentHeight: 200, lineHeight: 20, maxLines: 8) == 160)
        precondition(UMComposerSizing.shouldScroll(contentHeight: 200, lineHeight: 20, maxLines: 8))
        precondition(!UMComposerSizing.shouldScroll(contentHeight: 160, lineHeight: 20, maxLines: 8))
        print("PASS: eighth-line cap enables internal scrolling only beyond the cap")
    }
}
