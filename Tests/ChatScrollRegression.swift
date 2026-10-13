import Foundation

@main
struct ChatScrollRegression {
    static func main() {
        let closed = ChatScrollBounds(contentHeight: 1000, containerHeight: 600, topInset: 100, bottomInset: 0)
        let keyboard = ChatScrollBounds(contentHeight: 1000, containerHeight: 300, topInset: 100, bottomInset: 0)
        let inset = ChatScrollBounds(contentHeight: 1000, containerHeight: 600, topInset: 100, bottomInset: 80)
        let short = ChatScrollBounds(contentHeight: 40, containerHeight: 600, topInset: 100, bottomInset: 0)
        expect(closed.minimumY == -100 && closed.maximumY == 400, "scroll bounds include the header inset")
        expect(keyboard.maximumY == 700, "keyboard viewport has its own exact bottom offset")
        expect(inset.maximumY == 480, "bottom inset contributes to maximum legal offset")
        expect(short.maximumY == short.minimumY, "short content has no artificial scrolling slack")
        expect(closed.clampedY(700) == closed.maximumY, "viewport growth clamps overscroll")
        expect(keyboard.clampedY(-300) == keyboard.minimumY, "offset cannot precede the top edge")
        expect(closed.isAtBottom(offsetY: closed.maximumY), "manual true bottom is recognized")
        expect(!closed.isAtBottom(offsetY: closed.maximumY - 16), "sixteen points short is not bottom")

    }

    static func expect(_ condition: Bool, _ label: String) {
        guard condition else {
            print("FAIL: \(label)")
            exit(1)
        }
        print("PASS: \(label)")
    }
}
