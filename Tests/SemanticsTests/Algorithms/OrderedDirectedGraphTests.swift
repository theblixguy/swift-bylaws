import Testing
@testable import BylawsSemantics

@Suite("Ordered directed graph")
struct OrderedDirectedGraphTests {
  @Test("Graph keeps edge order and removes duplicate edges")
  func preservesEdgeOrderAndRemovesDuplicates() {
    let graph = OrderedDirectedGraph(
      nodes: ["A", "B", "C"],
      edges: [
        .init(from: "A", to: "C"),
        .init(from: "A", to: "B"),
        .init(from: "A", to: "C"),
      ]
    )

    #expect(graph.successors(of: "A") == ["C", "B"])
    #expect(graph.predecessors(of: "C") == ["A"])
    #expect(graph.outDegree(of: "A") == 2)
    #expect(graph.inDegree(of: "C") == 1)
  }

  @Test("Forward and reverse walks keep node order")
  func walksInBothDirections() {
    let graph = OrderedDirectedGraph(
      nodes: ["A", "B", "C", "D"],
      edges: [
        .init(from: "A", to: "B"),
        .init(from: "A", to: "C"),
        .init(from: "B", to: "D"),
        .init(from: "C", to: "D"),
        .init(from: "D", to: "A"),
      ]
    )

    #expect(graph.reachable(from: ["A"]) == ["B", "C", "D"])
    #expect(
      graph.reachable(from: ["D"], direction: .reverse)
        == ["B", "C", "A"]
    )
  }

  @Test("Cycle search returns the first closed path")
  func findsCycle() {
    let graph = OrderedDirectedGraph(
      nodes: ["A", "B", "C", "D"],
      edges: [
        .init(from: "A", to: "B"),
        .init(from: "B", to: "C"),
        .init(from: "C", to: "B"),
        .init(from: "C", to: "D"),
      ]
    )

    #expect(graph.firstCycle() == ["B", "C", "B"])
  }

  @Test("Cycle search handles a deep graph without cycles")
  func handlesDeepGraph() {
    let nodes = Array(0..<10000)
    let edges = zip(nodes, nodes.dropFirst()).map(DirectedEdge.init)

    #expect(OrderedDirectedGraph(nodes: nodes, edges: edges)
      .firstCycle() == nil)
  }
}
