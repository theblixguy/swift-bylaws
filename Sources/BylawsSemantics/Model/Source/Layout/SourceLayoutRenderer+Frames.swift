extension SourceLayoutRenderer {
  enum Request {
    case text(String)
    case document(
      SourceLayoutDocument, context: Context,
      following: SourceLayoutContinuation, trimmed: Bool
    )
    case line([Event], at: Placement, tabWidth: Int)
  }

  enum Step {
    case complete(String)
    case render(Request)
  }

  private enum Frame {
    case document(Writer, trimmed: Bool)
    case line(LineWriter)

    consuming func advance(after value: String?) throws -> (Step, Frame?) {
      switch consume self {
      case .document(var writer, let trimmed):
        switch try writer.advance(after: value) {
        case let .complete(result):
          (
            .complete(trimmed ? SourceLayoutPrepared.trim(result) : result),
            nil
          )
        case let .render(request):
          (.render(request), .document(writer, trimmed: trimmed))
        }
      case var .line(writer):
        switch try writer.advance(after: value) {
        case let .complete(result): (.complete(result), nil)
        case let .render(request): (.render(request), .line(writer))
        }
      }
    }
  }

  static func render(_ request: Request) throws -> String {
    var frames: [Frame] = []
    var next = Step.render(request)
    while true {
      let frame: Frame
      let value: String?
      switch consume next {
      case let .render(request):
        value = nil
        switch request {
        case let .text(text):
          next = .complete(text)
          continue
        case let .document(document, context, following, trimmed):
          guard context.defaultWidth > 0
          else { throw SourceLayoutError.widthMustBePositive }
          frame = .document(
            Writer(document: document, context: context, followedBy: following),
            trimmed: trimmed
          )
        case let .line(events, placement, tabWidth):
          frame = .line(LineWriter(
            events: events,
            at: placement,
            tabWidth: tabWidth
          ))
        }
      case let .complete(result):
        guard let parent = frames.popLast() else { return result }
        frame = parent
        value = result
      }
      let (step, suspended) = try frame.advance(after: value)
      if let suspended { frames.append(suspended) }
      next = step
    }
  }
}
