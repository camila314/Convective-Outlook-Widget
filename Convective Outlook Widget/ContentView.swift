import SwiftUI
import StoreKit

// for alerts, i like this better than having a trillion bools
// a little hacky because setting it to false does nothing but i address this
extension Binding where Value == Bool {
    static func mapped<T: Equatable>(_ binding: Binding<T>, to value: T) -> Binding<Bool> {
        Binding<Bool>(
            get: { binding.wrappedValue == value },
            set: {
                if $0 {
                    binding.wrappedValue = value
                }
            }
        )
    }
}

struct ColorKey: View {
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 15, height: 15)
            Text(label)
            Spacer(minLength: 0)
        }
    }
    
    init(_ label: String, _ color: Color) {
        self.label = label
        self.color = color
    }
}

struct TickerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color.white)
            .font(.system(size: 30))
            // very important btw
            .opacity(configuration.isPressed || !isEnabled ? 0.4 : 1.0)
    }
}

// swiftui why do you do this to me
struct BasicKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct ContentView: View {
    let colors: [Color] = [
        Color(red: 0.22, green: 0.24, blue: 0.3),
        .black
    ]

    @State private var day: UInt8 = 1
    @State private var scrollToTop: Bool = true

    // cutesy
    @State private var spinHeart: Bool = false
    @State private var fillHeart: Bool = false
    @State private var heartPopup: Bool = false

    @State private var tipPressed: Bool = false
    @State private var tipError: Bool = false
    @State private var tipSuccess: Bool = false
    
    enum AlertState {
        case none
        case heartPressed
        case tipPressed
        case tipSuccess
        case tipError
    }
    @State var alertState: AlertState = .none

    @AppStorage("pressHeart") var pressHeart: Bool = false
    @AppStorage("timesOpened") var timesOpened: Int = 0
    
    var body: some View {
        return NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        self.alertState = .heartPressed
                        self.pressHeart = true
                    }, label: {
                        Image(systemName: fillHeart ? "heart.fill" : "heart")
                            .font(.title)
                            .foregroundColor(Color.pink)
                            .padding()
                            .rotationEffect(.degrees(spinHeart ? 360 : 0))
                            .animation(fillHeart ? .easeIn(duration: 0.5) : .easeOut(duration: 0.5), value: fillHeart)
                            .animation(.bouncy(duration: 1), value: spinHeart)
                            .onAppear { timesOpened += 1 }
                            .task {
    #if targetEnvironment(simulator)
                                let doThis = true
    #else
                                let doThis = timesOpened > 3 && !pressHeart
    #endif
                                
                                if doThis {
                                    try? await Task.sleep(for: .seconds(3))
                                    
                                    fillHeart = true
                                    try? await Task.sleep(for: .seconds(0.25))
                                    spinHeart = true
                                    try? await Task.sleep(for: .seconds(0.75))
                                    fillHeart = false
                                }
                            }
                    })
                    
                    Spacer()

                    Button(action: {}, label: {
                        Image(systemName: "gear")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    })
                }
                .background(colors[0])
                alerts
                scrollBody
            }
            .background(scrollToTop ? colors[0] : Color.black)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarHidden(true)
            #else
            .toolbar(.hidden)
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private var alerts: some View {
        ZStack {
            Color.clear
                .frame(height: 0)
                .alert("Do you like my app?", isPresented: .mapped($alertState, to: .heartPressed)) {
                    VStack {
                        Button("Tip me!") { alertState = .tipPressed }
                        Button("Write a review") { alertState = .none }
                        Button("Contact me") { alertState = .none }
                        Button("Cancel", role: .cancel) { alertState = .none }
                    }
                } message: {
                    Text("""
                I worked pretty hard on this app and \
                I publish it for free out of my own pocket. \
                I would really appreciate if you could leave a tip \
                or a review if you like it. Thank you!
                """)
                }
            Color.clear
                .frame(height: 0)
                .alert("Tip Options", isPresented: .mapped($alertState, to: .tipPressed)) {
                    Button("Small Tip: $1") { Task {
                        guard
                            let product = try? await Product.products(for: ["small_tip"]).first,
                            let result = try? await product.purchase()
                        else {
                            alertState = .tipError
                            return
                        }
                        switch result {
                         case .success(let result):
                            if case .verified(let transaction) = result {
                                await transaction.finish()
                            }
                            // it's fine i guess
                            if case .unverified(let transaction, _) = result {
                                await transaction.finish()
                            }
                            alertState = .tipSuccess
                            break
                         default:
                            alertState = .none
                            break
                         }
                    }}
                    Button("Medium Tip: $5") { alertState = .none }
                    Button("Huge Tip: $20") { alertState = .none }
                    Button("Cancel", role: .cancel) { alertState = .none }
                }
            Color.clear
                .frame(height: 0)
                .alert("Tip Error", isPresented: .mapped($alertState, to: .tipError)) {
                    Button("Close") { alertState = .none }
                } message: {
                    Text("Failed to load the purchase. Try again later!")
                }
            Color.clear
                .frame(height: 0)
                .alert("Thank you!", isPresented: .mapped($alertState, to: .tipSuccess)) {
                    Button("Close") { alertState = .none }
                } message: {
                    Text("Thank you so much for tipping! I appreciate your support <3")
                }
        }
    }

    private var scrollBody: some View {
        let url = Bundle.main.url(forResource:"us-states", withExtension:"geojson");
        let parsed = try! Data(contentsOf: url!)
        let decoded = try! JSONDecoder().decode(GeoJSON.self, from: parsed)
        
        let url2 = Bundle.main.url(forResource:"outlook_test", withExtension:"geojson");
        let parsed2 = try! Data(contentsOf: url2!)
        let decoded2 = try! JSONDecoder().decode(GeoJSON.self, from: parsed2)
        
        return ScrollView(showsIndicators: false) {
            // all this to make colors not weird in the bg
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: BasicKey.self,
                        value: proxy.frame(in: .global).minY > 0
                    )
            }.onPreferenceChange(BasicKey.self) {
                scrollToTop = $0
            }.frame(height: 10)
            
            VStack {
                HStack {
                    Button(action: {
                        self.day = max(self.day - 1, 1)
                    }, label: { Image(systemName:"chevron.left") })
                    .buttonStyle(TickerButtonStyle())
                    .disabled(self.day <= 1)
                    Spacer(minLength: 0)
                    Text("Convective Outlook Day \(self.day)")
                        .font(.system(size: 25))
                    Spacer(minLength: 0)
                    Button(action: {
                        self.day = min(self.day + 1, 3)
                    }, label: { Image(systemName:"chevron.right") })
                    .buttonStyle(TickerButtonStyle())
                    .disabled(self.day >= 3)
                }
                .frame(height: 40)
                .padding(.horizontal, 15.0)
                
                Picker(selection: .constant(1), label: Text("Picker")) {
                    Text("Cat.").tag(1)
                    Text("Tornado").tag(2)
                    Text("Wind").tag(3)
                    Text("Hail").tag(4)
                }
                .pickerStyle(.segmented)
                
                GeographicView(features: decoded.features + decoded2.features)
                HStack {
                    ColorKey("Storms", Color(red: 0.7, green: 1, blue: 0.7))
                    Spacer(minLength: 0)
                    ColorKey("Slight", Color(red: 1, green: 1, blue: 0))
                    Spacer(minLength: 0)
                    ColorKey("Moderate", Color(red: 1, green: 0, blue: 0))
                }
                HStack {
                    ColorKey("Marginal", Color(red: 0, green: 0.7, blue: 0))
                    Spacer(minLength: 0)
                    ColorKey("Enhanced", Color(red: 1, green: 0.5, blue: 0))
                    Spacer(minLength: 0)
                    ColorKey("High", Color(red: 1, green: 0, blue: 1))
                }
                
                HStack {
                    Text("Forecast Discussion")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .underline()
                    Spacer()
                }.padding(.top)
                
                Text("Day 1 Convective Outlook   NWS Storm Prediction Center Norman OK 0745 AM CDT Wed May 27 2026  Valid 271300Z - 281200Z  ...THERE IS A SLIGHT RISK OF SEVERE THUNDERSTORMS ACROSS PARTS OF THE MID-ATLANTIC...  ...SUMMARY... Scattered severe thunderstorms are possible across parts of the Mid-Atlantic states this afternoon into the early evening.  Strong to severe gusts (50-65 mph) capable of wind damage will be the primary hazard with the stronger thunderstorms.  ...Mid-Atlantic/Ohio Valley... An upper-level trough over the Great Lakes will move southeast towards the upper OH Valley/Mid-Atlantic states during the period.  Water-vapor imagery this morning shows a lead disturbance over southern OH moving east across the central Appalachians.  In the low levels, an analyzed frontal zone has been modulated by ongoing showers/thunderstorms and it will move southeast today.  A moist airmass ahead of the front, featuring dewpoints in the upper 60s to lower 70s F, will gradually destabilize through early afternoon.  East-southeastward moving clusters are forecast to evolve by later this afternoon.  Scattered strong to severe gusts (50-65 mph) capable of wind damage will be the primary risk with the stronger thunderstorms, although marginally severe hail may accompany the stronger cores this afternoon.  ...Southern ID into eastern OR... A belt of strong easterly mid-level flow will remain over southwest ID into southeast OR to the north of a stationary, deep-layer cyclone over the Sierra Nevada.  Heating of an adequately moist boundary layer will steepen low-level lapse rates by early afternoon.  Widely scattered to scattered thunderstorms are forecast to develop this afternoon.  Forecast hodographs show 20-45 kt 700-500 mb flow (strongest over southeast OR) and mean storm motions 35-45 kt.  These flow fields coupled with evaporatively cooled downdrafts will likely result in a mix of quickly moving cells and smaller-scale linear clusters.  This activity will potentially be capable of severe gusts (60-75 mph) before diminishing by mid-late evening.    ...Western Great Lakes... Northwesterly mid-level flow will be in place across the western Great Lakes today, as a shortwave trough moves southeastward across the region.  At the surface, a pocket of maximized low-level moisture will be located over Wisconsin, where MLCAPE is expected to peak in the 1500 to 2500 J/kg range.  An isolated risk for large hail/damaging gusts are possible with the stronger thunderstorms.  ...Southern Texas Panhandle/West Texas/Far Western Oklahoma... Somewhat displaced from an expansive overnight MCS along the TX coast, an airmass featuring upper 50s to lower 60s F dewpoints will destabilize beneath a weak mid- to upper-level trough.  Widely scattered to scattered storms are forecast to develop by late afternoon and aggregate into small clusters this evening.  Isolated large hail/severe gusts are the primary severe hazards.  ..Smith/Weinman.. 05/27/2026")
                    .padding(.top, 1.0)
                    .padding(.bottom, 30.0)
                    .monospaced()
                    .font(.system(size: 13))
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 15.0)
            .background(GeometryReader { geo in
                LinearGradient(
                    colors: self.colors,
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 350 / geo.size.height)
                )
            })
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ContentView()
}
