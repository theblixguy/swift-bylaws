package struct DirectedEdge<Node: Hashable & Sendable>: Hashable, Sendable {
  package let source: Node
  package let destination: Node

  package init(from source: Node, to destination: Node) {
    self.source = source
    self.destination = destination
  }
}

package struct OrderedDirectedGraph<Node: Hashable & Sendable>: Sendable {
  package enum Direction: Sendable {
    case forward
    case reverse
  }

  package let nodes: [Node]
  private let successorsByNode: [Node: [Node]]
  private let predecessorsByNode: [Node: [Node]]

  package init(nodes: [Node], edges: [DirectedEdge<Node>]) {
    var orderedNodes: [Node] = []
    var knownNodes: Set<Node> = []
    for node in nodes where knownNodes.insert(node).inserted {
      orderedNodes.append(node)
    }
    for edge in edges {
      if knownNodes.insert(edge.source).inserted {
        orderedNodes.append(edge.source)
      }
      if knownNodes.insert(edge.destination).inserted {
        orderedNodes.append(edge.destination)
      }
    }

    var successors: [Node: [Node]] = [:]
    var predecessors: [Node: [Node]] = [:]
    var knownEdges: Set<DirectedEdge<Node>> = []
    for edge in edges where knownEdges.insert(edge).inserted {
      successors[edge.source, default: []].append(edge.destination)
      predecessors[edge.destination, default: []].append(edge.source)
    }

    self.nodes = orderedNodes
    successorsByNode = successors
    predecessorsByNode = predecessors
  }

  package func successors(of node: Node) -> [Node] {
    successorsByNode[node, default: []]
  }

  package func predecessors(of node: Node) -> [Node] {
    predecessorsByNode[node, default: []]
  }

  package func outDegree(of node: Node) -> Int {
    successorsByNode[node, default: []].count
  }

  package func inDegree(of node: Node) -> Int {
    predecessorsByNode[node, default: []].count
  }

  package func reachable(
    from roots: some Sequence<Node>,
    direction: Direction = .forward
  ) -> [Node] {
    let roots = Array(roots)
    var seen = Set(roots)
    var queue = roots
    var index = 0
    var result: [Node] = []
    while index < queue.count {
      let node = queue[index]
      index += 1
      let neighbours = switch direction {
      case .forward: successors(of: node)
      case .reverse: predecessors(of: node)
      }
      for neighbour in neighbours where seen.insert(neighbour).inserted {
        result.append(neighbour)
        queue.append(neighbour)
      }
    }
    return result
  }

  package func firstCycle() -> [Node]? {
    var states: [Node: VisitState] = [:]
    var pathIndices: [Node: Int] = [:]

    for root in nodes where states[root] == nil {
      states[root] = .visiting
      pathIndices[root] = 0
      var stack = [Frame(node: root)]

      while !stack.isEmpty {
        let frameIndex = stack.count - 1
        let node = stack[frameIndex].node
        let successors = successors(of: node)
        guard stack[frameIndex].nextSuccessorIndex < successors.count else {
          states[node] = .visited
          pathIndices[node] = nil
          stack.removeLast()
          continue
        }

        let successor = successors[stack[frameIndex].nextSuccessorIndex]
        stack[frameIndex].nextSuccessorIndex += 1
        switch states[successor] {
        case .visiting:
          guard let cycleStart = pathIndices[successor] else {
            preconditionFailure("A visiting node must be on the active path.")
          }
          return stack[cycleStart...].map(\.node) + [successor]
        case .visited:
          continue
        case nil:
          states[successor] = .visiting
          pathIndices[successor] = stack.count
          stack.append(Frame(node: successor))
        }
      }
    }
    return nil
  }

  private enum VisitState {
    case visiting
    case visited
  }

  private struct Frame {
    let node: Node
    var nextSuccessorIndex = 0
  }
}
