//
//  ServiceStatus.swift
//  MonitorGlucoseServiceKitUI
//
//  Created by Pete Schwamb on 9/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import MonitorGlucoseServiceKit

struct ServiceStatusView: View, HorizontalSizeClassOverride {
    @Environment(\.dismissAction) private var dismiss

    @ObservedObject var viewModel: ServiceStatusViewModel
    @ObservedObject var otpViewModel: OTPViewModel
    @State private var selectedItem: String?
    /// Tells this phone apart on the sites (both phones of a family can run Loop).
    @AppStorage("MonitorGlucose.phoneName") private var phoneName = ""
    /// A spare phone: uploads nothing to the sites, takes no remote commands.
    @AppStorage("MonitorGlucose.backupPhone") private var backupPhone = false
    var body: some View {
        VStack {
            Text("Monitor Glucose")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Image(frameworkImage: "glucosemonitor", decorative: true)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 150, height: 150)
            

            VStack(spacing: 0) {
                HStack {
                    Text("URL")
                    Spacer()
                    Text(viewModel.urlString)
                }
                .padding()
                Divider()
                HStack {
                    Text("Status")
                    Spacer()
                    Text(String(describing: viewModel.status))
                }
                .padding()
                Divider()
                NavigationLink(destination: OTPSelectionView(otpViewModel: otpViewModel), tag: "otp-view", selection: $selectedItem) {
                    HStack {
                        Text("One-Time Password")
                        Spacer()
                        Text(otpViewModel.otpCode)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }.foregroundColor(Color.primary)
                .padding()
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Phone name")
                    Spacer()
                    TextField("Valérie", text: $phoneName)
                        .multilineTextAlignment(.trailing)
                        .disableAutocorrection(true)
                }
                .padding()
                Divider()
                Toggle("Backup phone", isOn: $backupPhone)
                    .padding()
                Text(backupPhone
                     ? "This phone uploads nothing to Nightscout or your server, so it never takes the remote commands meant for the Looper's phone."
                     : "The name is shown on the sites and in the Monitor Glucose apps, so two phones running Loop can be told apart.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding([.leading, .trailing, .bottom])
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.top, 12)

            Button(action: {
                viewModel.didLogout?()
            } ) {
                Text("Logout").padding(.top, 20)
            }
        }
        .padding([.leading, .trailing])
        .navigationBarTitle("")
        .navigationBarItems(trailing: dismissButton)
    }
    
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Done").bold()
        }
    }
}
