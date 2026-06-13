import SwiftUI

/// 주행 종료 후 목록·건강·캘린더·파일 저장 진행을 표시한다.
struct RideSaveProgressView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        if let progress = session.saveProgress {
            content(progress)
        }
    }

    private func content(_ progress: RideSession.RideSaveProgress) -> some View {
        VStack(spacing: 20) {
            header(progress)
            stepList(progress)
            footer(progress)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .interactiveDismissDisabled(!progress.isComplete)
    }

    private func header(_ progress: RideSession.RideSaveProgress) -> some View {
        VStack(spacing: 8) {
            if progress.isComplete {
                Image(systemName: progress.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(progress.failedCount == 0 ? Theme.green : Theme.gold)
            } else {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Theme.gold)
            }
            Text(progress.isComplete ? "저장 완료" : "라이딩 저장 중…")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(progress.rideName)
                .font(.subheadline)
                .foregroundColor(Theme.label)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func stepList(_ progress: RideSession.RideSaveProgress) -> some View {
        VStack(spacing: 0) {
            ForEach(progress.steps) { step in
                stepRow(step)
                if step.id != progress.steps.last?.id {
                    Divider().background(Theme.cardBorder)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
    }

    private func stepRow(_ step: RideSession.RideSaveProgress.Step) -> some View {
        HStack(spacing: 12) {
            stepIcon(step.status)
                .frame(width: 24)
            Text(step.title)
                .font(.body)
                .foregroundColor(.white)
            Spacer()
            statusLabel(step.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func stepIcon(_ status: RideSession.RideSaveProgress.Step.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(Theme.label.opacity(0.5))
        case .running:
            ProgressView()
                .tint(Theme.gold)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.red)
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: RideSession.RideSaveProgress.Step.Status) -> some View {
        switch status {
        case .pending:
            Text("대기")
                .font(.caption)
                .foregroundColor(Theme.label.opacity(0.6))
        case .running:
            Text("진행 중")
                .font(.caption)
                .foregroundColor(Theme.gold)
        case .success:
            Text("완료")
                .font(.caption)
                .foregroundColor(Theme.green)
        case .failed:
            Text("실패")
                .font(.caption)
                .foregroundColor(Theme.red)
        }
    }

    private func footer(_ progress: RideSession.RideSaveProgress) -> some View {
        Group {
            if progress.isComplete {
                VStack(spacing: 12) {
                    if progress.failedCount > 0 {
                        Text("\(progress.failedCount)개 항목 저장에 실패했습니다.\n권한 설정을 확인해 주세요.")
                            .font(.footnote)
                            .foregroundColor(Theme.label)
                            .multilineTextAlignment(.center)
                    }
                    Button("확인") { session.dismissSaveProgress() }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.gold))
                }
            } else {
                Text("잠시만 기다려 주세요…")
                    .font(.footnote)
                    .foregroundColor(Theme.label)
            }
        }
    }
}
