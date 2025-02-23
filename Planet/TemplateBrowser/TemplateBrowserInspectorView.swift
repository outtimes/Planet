//
//  TemplateBrowserInspectorView.swift
//  Planet
//
//  Created by Kai on 12/5/22.
//

import SwiftUI

struct TemplateBrowserInspectorView: View {
    @StateObject private var store: TemplateStore

    init() {
        _store = StateObject(wrappedValue: TemplateStore.shared)
    }

    var body: some View {
        ScrollView {
            if let templateID = store.selectedTemplateID, let template = store.templates.first(where: { $0.id == templateID }) {
                Section {
                    VStack {
                        HStack {
                            Text(template.name)
                                .font(.headline)
                            Spacer(minLength: 1)
                        }
                        HStack {
                            Text(template.description)
                            Spacer(minLength: 1)
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 12)

                Spacer()
            } else {
                Spacer()
                Text("No Template Selected")
                Spacer()
            }
        }
        .frame(minWidth: .templateInspectorWidth, maxWidth: .templateInspectorMaxWidth, minHeight: .templateContentHeight, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct TemplateBrowserInspectorView_Previews: PreviewProvider {
    static var previews: some View {
        TemplateBrowserInspectorView()
    }
}
