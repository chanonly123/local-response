//
//  ErrorsView.swift
//  Local Response Mapper
//
//  Created by Chandan on 23/08/24.
//

import SwiftUI

struct ErrorsView: View {

    let errors: [any Error]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(errors.indices, id: \.self) { i in
                VStack {
                    Text("\(errors[i])")
                }
                .padding(8)
                .background(Color(hex: 0xff795b))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(width: 250)
    }
}

extension View {

    func showErrors(errors: [any Error]) -> some View {
        self.overlay(alignment: .topTrailing) {
            ErrorsView(errors: errors)
                .padding()
        }
    }
}

protocol ObservableObjectErrors: AnyObject {
    @MainActor var errors: [any Error] { get set }
}

extension ObservableObjectErrors {
    @MainActor
    func appendError(_ err: any Error) {
        withAnimation {
            errors.append(err)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if !self.errors.isEmpty {
                    self.errors.removeFirst()
                }
            }
        }
    }
}

#Preview {
    VStack {
        Text("Content")
    }
    .frame(width: 400, height: 500)
    .showErrors(errors: [
        NSError(domain: "Something went wrong!", code: -1),
        NSError(domain: "Something went wrong!", code: -1),
        NSError(domain: "Something went wrong!", code: -1),
        NSError(domain: "Something went wrong!", code: -1),
        NSError(domain: "Something went wrong!", code: -1),
    ])
}

