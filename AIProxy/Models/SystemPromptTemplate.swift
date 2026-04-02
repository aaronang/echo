import Foundation

struct SystemPromptTemplate: Identifiable {
    let id: String
    let name: String
    let content: String

    static let all: [SystemPromptTemplate] = [
        .init(id: "blank",   name: "Blank",            content: ""),
        .init(id: "coding",  name: "Coding Assistant", content: "You are an expert software engineer. Answer concisely and provide working code examples."),
        .init(id: "review",  name: "Code Review",      content: "You are a senior code reviewer. Identify bugs, suggest improvements, and explain your reasoning clearly."),
        .init(id: "writer",  name: "Technical Writer", content: "You are a technical documentation writer. Produce clear, accurate, and well-structured content."),
        .init(id: "support", name: "Customer Support", content: "You are a friendly and helpful customer support agent. Resolve issues efficiently and professionally."),
    ]
}
