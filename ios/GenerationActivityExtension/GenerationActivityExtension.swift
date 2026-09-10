import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct GenerationActivityExtensionBundle: WidgetBundle {
  var body: some Widget {
    KelivoGenerationActivityWidget()
    VoiceChatActivityWidget()
  }
}

// ---------------------------------------------------------------------------
// 文本生成实时活动
// ---------------------------------------------------------------------------

struct KelivoGenerationActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: KelivoGenerationActivityAttributes.self) { context in
      HStack(spacing: 12) {
        Image(systemName: symbol(context.state, stale: activityIsStale(context)))
          .font(.title2).foregroundStyle(activityIsStale(context) ? .orange : .blue)
        VStack(alignment: .leading, spacing: 4) {
          Text(context.state.displayTitle).font(.headline).lineLimit(1)
          Text(activityIsStale(context) ? context.state.staleMessage : context.state.detail)
            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
          if context.state.tokenCount > 0 {
            Text("\(context.state.tokenCount) tokens").font(.caption2).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 4)
        GenerationElapsedTime(state: context.state).font(.caption.monospacedDigit())
          .frame(width: 64, alignment: .trailing)
      }
      .padding(16)
      .widgetURL(conversationURL(context.state.conversationId))
      .activityBackgroundTint(Color(.secondarySystemBackground))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: symbol(context.state, stale: activityIsStale(context))).foregroundStyle(.blue)
            .font(.title3)
        }
        DynamicIslandExpandedRegion(.trailing) {
          GenerationElapsedTime(state: context.state).font(.caption.monospacedDigit())
            .frame(width: 64, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Text(context.state.displayTitle).font(.headline).lineLimit(1)
            Text(activityIsStale(context) ? context.state.staleMessage : context.state.detail)
              .font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 6)
          .padding(.horizontal, 4)
          .padding(.bottom, 10)
        }
      } compactLeading: {
        Image(systemName: symbol(context.state, stale: activityIsStale(context))).foregroundStyle(.blue)
      } compactTrailing: {
        if context.state.activeTaskCount > 1 {
          Text("\(context.state.activeTaskCount)").monospacedDigit()
        } else {
          GenerationElapsedTime(state: context.state).font(.caption2.monospacedDigit())
            .frame(width: 48, alignment: .trailing)
        }
      } minimal: {
        Image(systemName: symbol(context.state, stale: activityIsStale(context))).foregroundStyle(.blue)
      }
      .widgetURL(conversationURL(context.state.conversationId))
      .keylineTint(.blue)
      .contentMargins(.horizontal, 20, for: .expanded)
    }
  }
}

// ---------------------------------------------------------------------------
// 实时语音对话灵动岛 (VoiceChat Live Activity & Dynamic Island)
// ---------------------------------------------------------------------------

struct VoiceChatActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: VoiceChatActivityAttributes.self) { context in
      VoiceChatLockScreenView(context: context)
        .activityBackgroundTint(Color(red: 0.05, green: 0.07, blue: 0.12))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        // 展开态 - 顶部左侧：头像与状态
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 8) {
            VoiceAssistantAvatar(avatarPath: context.attributes.avatarPath)
              .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
              Text(context.attributes.assistantName.isEmpty ? "AI 助手" : context.attributes.assistantName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)

              Text(context.state.stateLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(voiceStateColor(state: context.state.state))
                .lineLimit(1)
            }
          }
          .padding(.leading, 6)
        }

        // 展开态 - 顶部右侧：动态波形
        DynamicIslandExpandedRegion(.trailing) {
          DynamicWaveformView(
            waveLevel: context.state.waveLevel,
            color: voiceStateColor(state: context.state.state)
          )
          .frame(width: 44, height: 18)
          .padding(.trailing, 6)
        }

        // 展开态 - 中部与底部：实时字幕与停止按钮
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            // 实时字幕转写
            Text(context.state.transcript.isEmpty ? "正在聆听您的声音..." : context.state.transcript)
              .font(.system(size: 13, weight: .regular))
              .foregroundColor(.white.opacity(0.92))
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 4)

            // 底部操作区：停止按钮
            HStack {
              Spacer()
              if #available(iOS 17.0, *) {
                Button(intent: StopVoiceChatIntent()) {
                  HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                      .font(.system(size: 10, weight: .bold))
                    Text("停止")
                      .font(.system(size: 12, weight: .semibold))
                  }
                  .padding(.horizontal, 12)
                  .padding(.vertical, 5)
                  .background(Color.red.opacity(0.88))
                  .foregroundColor(.white)
                  .clipShape(Capsule())
                }
                .buttonStyle(.plain)
              } else {
                Link(destination: URL(string: "kelivo://voice/stop")!) {
                  HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                      .font(.system(size: 10, weight: .bold))
                    Text("停止")
                      .font(.system(size: 12, weight: .semibold))
                  }
                  .padding(.horizontal, 12)
                  .padding(.vertical, 5)
                  .background(Color.red.opacity(0.88))
                  .foregroundColor(.white)
                  .clipShape(Capsule())
                }
              }
            }
            .padding(.trailing, 4)
            .padding(.bottom, 2)
          }
          .padding(.horizontal, 4)
          .padding(.top, 4)
        }
      } compactLeading: {
        // 紧凑态左侧：微型波形或麦克风
        HStack(spacing: 3) {
          Image(systemName: context.state.state == "aiSpeaking" ? "waveform" : "mic.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(voiceStateColor(state: context.state.state))
        }
      } compactTrailing: {
        // 紧凑态右侧：简要状态标签
        Text(compactStateLabel(state: context.state.state))
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(voiceStateColor(state: context.state.state))
      } minimal: {
        Image(systemName: context.state.state == "aiSpeaking" ? "waveform" : "mic.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(voiceStateColor(state: context.state.state))
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 锁屏实时卡片 View
// ---------------------------------------------------------------------------

private struct VoiceChatLockScreenView: View {
  let context: ActivityViewContext<VoiceChatActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        VoiceAssistantAvatar(avatarPath: context.attributes.avatarPath)
          .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.assistantName.isEmpty ? "AI 语音助手" : context.attributes.assistantName)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundColor(.white)

          Text(context.state.stateLabel)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(voiceStateColor(state: context.state.state))
        }

        Spacer()

        DynamicWaveformView(
          waveLevel: context.state.waveLevel,
          color: voiceStateColor(state: context.state.state)
        )
        .frame(width: 48, height: 20)
      }

      Text(context.state.transcript.isEmpty ? "正在聆听..." : context.state.transcript)
        .font(.subheadline)
        .foregroundColor(.white.opacity(0.9))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Spacer()
        if #available(iOS 17.0, *) {
          Button(intent: StopVoiceChatIntent()) {
            HStack(spacing: 4) {
              Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
              Text("停止")
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.85))
            .foregroundColor(.white)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        } else {
          Link(destination: URL(string: "kelivo://voice/stop")!) {
            HStack(spacing: 4) {
              Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
              Text("停止")
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.85))
            .foregroundColor(.white)
            .clipShape(Capsule())
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      LinearGradient(
        colors: [Color(red: 0.08, green: 0.11, blue: 0.18), Color(red: 0.04, green: 0.05, blue: 0.09)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }
}

// ---------------------------------------------------------------------------
// 辅助子组件
// ---------------------------------------------------------------------------

private struct VoiceAssistantAvatar: View {
  let avatarPath: String?

  var body: some View {
    if let path = avatarPath, !path.isEmpty, let uiImage = UIImage(contentsOfFile: path) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    } else {
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [Color(red: 0.38, green: 0.65, blue: 0.98), Color(red: 0.65, green: 0.54, blue: 0.98)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        Image(systemName: "waveform")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.white)
      }
    }
  }
}

private struct DynamicWaveformView: View {
  let waveLevel: Double
  let color: Color

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(0..<5) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(color)
          .frame(
            width: 3,
            height: barHeight(index: index, level: waveLevel)
          )
      }
    }
  }

  private func barHeight(index: Int, level: Double) -> CGFloat {
    let normalized = max(0.1, min(1.0, level))
    let multipliers: [Double] = [0.4, 0.8, 1.0, 0.7, 0.5]
    let base: Double = 4.0
    let maxExtra: Double = 14.0
    return CGFloat(base + maxExtra * normalized * multipliers[index])
  }
}

private func voiceStateColor(state: String) -> Color {
  switch state {
  case "listening":
    return Color(red: 0.38, green: 0.65, blue: 0.98) // 柔和天蓝
  case "processing":
    return Color(red: 0.65, green: 0.54, blue: 0.98) // 紫色思考
  case "aiSpeaking":
    return Color(red: 0.20, green: 0.83, blue: 0.60) // 清新翡翠绿
  default:
    return Color.gray
  }
}

private func compactStateLabel(state: String) -> String {
  switch state {
  case "listening":
    return "在听呢"
  case "processing":
    return "思考中"
  case "aiSpeaking":
    return "回复中"
  default:
    return "就绪"
  }
}

private func symbol(_ state: KelivoGenerationActivityAttributes.ContentState, stale: Bool) -> String {
  if stale { return "exclamationmark.circle" }
  switch state.outcome {
  case "completed": return "checkmark.circle.fill"
  case "failed", "interrupted": return "exclamationmark.circle.fill"
  case "cancelled": return "stop.circle"
  default: return "sparkles"
  }
}

private func conversationURL(_ id: String) -> URL? {
  var components = URLComponents()
  components.scheme = "kelivo"
  components.host = "conversation"
  components.path = "/\(id)"
  return components.url
}

private struct GenerationElapsedTime: View {
  let state: KelivoGenerationActivityAttributes.ContentState

  var body: some View {
    Group {
      if let end = state.finishedAt {
        let seconds = max(0, Int(end.timeIntervalSince(state.startedAt)))
        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
      } else {
        // WidgetKit owns the timer; no per-second ActivityKit updates.
        Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(8 * 3600), countsDown: false)
      }
    }
    // Timer Text fills the offered width; frame alignment alone aligns its
    // container, leaving the changing digits at the leading edge.
    .multilineTextAlignment(.trailing)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

private func activityIsStale(_ context: ActivityViewContext<KelivoGenerationActivityAttributes>) -> Bool {
  if #available(iOS 16.2, *) { return context.isStale }
  return false
}
