//
//  SettingsView.swift
//  Convective Outlook Widget
//
//  Created by Full Name on 5/31/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showLocation") var showLocation: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var locationDenied: Bool = false
    @State private var locationRestricted: Bool = false

    private func locationCheck() {
        if showLocation {
            Task {
                switch await LocationManager.shared.request() {
                case .denied:
                    locationDenied = true
                    showLocation = false
                case .restricted:
                    locationRestricted = true
                    showLocation = false
                default:
                    return
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }.buttonStyle(TickerButtonStyle())
                    Spacer()
                }
                
                Text("Settings")
                    .font(.system(size: 30))
            }
            .frame(height: 65)
            .padding(.horizontal)
            VStack {
                GeometryReader { geometry in
                    Toggle("Show Location", isOn: $showLocation)
                        .scaleEffect(1.2, anchor: .leading)
                        .frame(width: geometry.size.width / 1.2)
                        .onChange(of: showLocation, self.locationCheck)
                        .onAppear(perform: self.locationCheck)
                        .alert("Enable location", isPresented: $locationDenied) {
#if os(iOS)
                            Button("Open Settings") {
                                Task { await UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                            }
                            Button("Cancel", role: .cancel) {}
#else
                            Button("Ok", role: .cancel) {}
#endif
                        } message: {
                            Text("Open your settings app to update your location permissions")
                        }
                        .alert("Location Restricted", isPresented: $locationRestricted) {
                            Button("Ok", role: .cancel) {}
                        } message: {
                            Text("Unable to access location data")
                        }
                }.padding()
                Spacer()
            }
            .background(LinearGradient(
                colors: ContentView.colors,
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        .navigationTitle("Settings")
        .background(ContentView.colors[0])
#if os(iOS)
        .navigationBarHidden(true)
#else
        .toolbar(.hidden)
#endif
    }
}

#Preview {
    return SettingsView()
}
