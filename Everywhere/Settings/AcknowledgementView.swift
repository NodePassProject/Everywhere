//
//  AcknowledgementView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI

struct AcknowledgementView: View {
    var body: some View {
        List(Acknowledgement.all) { item in
            NavigationLink {
                AcknowledgementDetailView(item: item)
            } label: {
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(item.license)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AcknowledgementDetailView: View {
    let item: Acknowledgement

    var body: some View {
        Form {
            Section {
                Link(destination: item.url) {
                    HStack {
                        Text(item.url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("Repository")
            }

            Section {
                Text(item.licenseText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text(item.license)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct Acknowledgement: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let license: String
    let licenseText: String

    static let all: [Acknowledgement] = [
        Acknowledgement(
            name: "Xray-core",
            url: URL(string: "https://github.com/XTLS/Xray-core")!,
            license: "MPL 2.0",
            licenseText: Licenses.mpl2
        ),
        Acknowledgement(
            name: "sing-box",
            url: URL(string: "https://github.com/SagerNet/sing-box")!,
            license: "GPL-3.0",
            licenseText: """
            Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>

            \(Licenses.gpl3)
            """
        ),
        Acknowledgement(
            name: "mihomo",
            url: URL(string: "https://github.com/MetaCubeX/mihomo")!,
            license: "GPL-3.0",
            licenseText: """
            Copyright (C) 2024 MetaCubeX

            \(Licenses.gpl3)
            """
        ),
        Acknowledgement(
            name: "tun2socks",
            url: URL(string: "https://github.com/xjasonlyu/tun2socks")!,
            license: "MIT",
            licenseText: Licenses.mit(copyright: "Copyright (c) 2019 Jason Lyu")
        ),
        Acknowledgement(
            name: "Yacd-meta",
            url: URL(string: "https://github.com/MetaCubeX/Yacd-meta")!,
            license: "MIT",
            licenseText: Licenses.mit(copyright: "Copyright (c) 2019 Haishan Hu")
        ),
        Acknowledgement(
            name: "Runestone",
            url: URL(string: "https://github.com/simonbs/Runestone")!,
            license: "MIT",
            licenseText: Licenses.mit(copyright: "Copyright (c) 2021 Simon Støvring")
        ),
    ]
}

private enum Licenses {
    static func mit(copyright: String) -> String {
        """
        MIT License

        \(copyright)

        Permission is hereby granted, free of charge, to any person obtaining a \
        copy of this software and associated documentation files (the "Software"), \
        to deal in the Software without restriction, including without limitation \
        the rights to use, copy, modify, merge, publish, distribute, sublicense, \
        and/or sell copies of the Software, and to permit persons to whom the \
        Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in \
        all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING \
        FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
        DEALINGS IN THE SOFTWARE.
        """
    }

    static let gpl3 = """
        This program is free software: you can redistribute it and/or modify it \
        under the terms of the GNU General Public License as published by the \
        Free Software Foundation, either version 3 of the License, or (at your \
        option) any later version.

        This program is distributed in the hope that it will be useful, but \
        WITHOUT ANY WARRANTY; without even the implied warranty of \
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU \
        General Public License for more details.

        You should have received a copy of the GNU General Public License along \
        with this program. If not, see <https://www.gnu.org/licenses/>.
        """

    static let mpl2 = """
        This Source Code Form is subject to the terms of the Mozilla Public \
        License, v. 2.0. If a copy of the MPL was not distributed with this \
        file, You can obtain one at https://mozilla.org/MPL/2.0/.
        """
}
