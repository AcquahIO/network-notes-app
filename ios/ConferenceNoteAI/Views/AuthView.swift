import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isRegistering = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Conference Note AI")
                    .font(Typography.titleXL)
                    .foregroundColor(AppColors.textPrimary)
                Text("Capture talks, slides, and AI summaries with one tap.")
                    .font(Typography.body)
                    .foregroundColor(AppColors.textSecondary)
            }
            VStack(spacing: Spacing.md) {
                TextField("Email", text: $authVM.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(AppColors.card)
                    .cornerRadius(12)
                SecureField("Password", text: $authVM.password)
                    .textContentType(.password)
                    .padding()
                    .background(AppColors.card)
                    .cornerRadius(12)
            }
            .foregroundColor(AppColors.textPrimary)

            Button(action: { Task { await submit() } }) {
                HStack {
                    Spacer()
                    Text(isRegistering ? "Create account" : "Sign in")
                        .font(Typography.callout)
                    Spacer()
                }
                .padding()
                .background(AppColors.accent)
                .foregroundColor(AppColors.background)
                .cornerRadius(14)
                .shadow(color: AppColors.shadow, radius: 12, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .scaleEffect(1.0, anchor: .center)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRegistering)

            Button(action: { isRegistering.toggle() }) {
                Text(isRegistering ? "Already have an account? Sign in" : "Need an account? Register")
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            Button(action: { authVM.continueAsGuest() }) {
                Text("Continue as guest (demo data)")
                    .font(Typography.caption)
                    .foregroundColor(AppColors.accent)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .background(AppTheme.backgroundGradient().ignoresSafeArea())
    }

    private func submit() async {
        if isRegistering {
            await authVM.register()
        } else {
            await authVM.login()
        }
    }
}
