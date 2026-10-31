import FitnessTrackerCore
import SwiftUI

/// A schematic map of the catalog's muscle groups, rather than an anatomical atlas.
struct ExerciseBodyPicker: View {
  @Environment(\.locale) private var locale
  @Binding var selection: MuscleGroup?
  @State private var showsBack = false

  var body: some View {
    VStack(spacing: 12) {
      Picker(L10n.text("Вид тела", locale: locale), selection: $showsBack) {
        Text(L10n.text("Спереди", locale: locale)).tag(false)
        Text(L10n.text("Сзади", locale: locale)).tag(true)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("exerciseBodySide")

      // One coordinate system keeps the drawing and its hit regions aligned at every width.
      GeometryReader { geometry in
        let scale = min(geometry.size.width / 300, 1)
        ZStack(alignment: .topLeading) {
          BodyOutline().fill(FitTheme.muted.opacity(0.14))
          Ellipse().fill(FitTheme.muted.opacity(0.22))
            .frame(width: 42, height: 50).offset(x: 129, y: 4)
          ForEach(regions) { region in
            Button {
              selection = selection == region.group ? nil : region.group
            } label: {
              BodyMusclePatch()
                .fill(selection == region.group ? FitTheme.accent : FitTheme.muted.opacity(0.4))
                .overlay {
                  BodyMusclePatch().strokeBorder(
                    selection == region.group ? Color.primary : Color.clear, lineWidth: 2)
                }
                .frame(width: region.width, height: region.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: region.x, y: region.y)
            .accessibilityLabel(L10n.text(region.group.title, locale: locale))
            .accessibilityValue(
              selection == region.group ? L10n.text("Выбрано", locale: locale) : ""
            )
            .accessibilityAddTraits(selection == region.group ? [.isSelected] : [])
            .accessibilityIdentifier("bodyMuscle_\(region.id)")
          }
        }
        .frame(width: 300, height: 400)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: max(0, (geometry.size.width - 300 * scale) / 2))
      }
      .frame(height: 400)

      HStack {
        Text(
          selection.map { L10n.text($0.title, locale: locale) }
            ?? L10n.text("Все мышцы", locale: locale)
        )
        .font(.headline)
        Spacer()
        if selection != nil {
          Button(L10n.text("Сбросить", locale: locale)) { selection = nil }
            .accessibilityIdentifier("clearBodyMuscle")
        }
      }
      Text(L10n.text("Нажмите на область тела, чтобы выбрать группу мышц.", locale: locale))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var regions: [BodyMuscleRegion] {
    var result = [
      BodyMuscleRegion(id: "leftShoulder", group: .shoulders, x: 64, y: 91, width: 44, height: 48),
      BodyMuscleRegion(
        id: "rightShoulder", group: .shoulders, x: 192, y: 91, width: 44, height: 48),
      BodyMuscleRegion(id: "leftArm", group: .arms, x: 41, y: 145, width: 44, height: 102),
      BodyMuscleRegion(id: "rightArm", group: .arms, x: 215, y: 145, width: 44, height: 102),
      BodyMuscleRegion(id: "leftLeg", group: .legs, x: 94, y: 256, width: 48, height: 126),
      BodyMuscleRegion(id: "rightLeg", group: .legs, x: 158, y: 256, width: 48, height: 126),
    ]
    if showsBack {
      result.append(
        BodyMuscleRegion(id: "back", group: .back, x: 108, y: 96, width: 84, height: 145))
    } else {
      result.append(
        BodyMuscleRegion(id: "chest", group: .chest, x: 108, y: 99, width: 84, height: 65))
      result.append(
        BodyMuscleRegion(id: "core", group: .core, x: 114, y: 173, width: 72, height: 68))
    }
    return result
  }
}

private struct BodyMuscleRegion: Identifiable {
  let id: String
  let group: MuscleGroup
  let x: CGFloat
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat
}

private struct BodyMusclePatch: InsettableShape {
  var insetAmount: CGFloat = 0
  func inset(by amount: CGFloat) -> Self {
    var copy = self
    copy.insetAmount += amount
    return copy
  }
  func path(in rect: CGRect) -> Path {
    let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
    return Path(roundedRect: bounds, cornerRadius: min(bounds.width, bounds.height) * 0.3)
  }
}

private struct BodyOutline: Shape {
  func path(in rect: CGRect) -> Path {
    let points: [CGPoint] = [
      .init(x: 133, y: 60), .init(x: 167, y: 60), .init(x: 173, y: 79),
      .init(x: 223, y: 91), .init(x: 238, y: 132), .init(x: 268, y: 248),
      .init(x: 249, y: 266), .init(x: 224, y: 215), .init(x: 207, y: 156),
      .init(x: 199, y: 221), .init(x: 216, y: 265), .init(x: 207, y: 389),
      .init(x: 161, y: 389), .init(x: 150, y: 280), .init(x: 139, y: 389),
      .init(x: 93, y: 389), .init(x: 84, y: 265), .init(x: 101, y: 221),
      .init(x: 93, y: 156), .init(x: 76, y: 215), .init(x: 51, y: 266),
      .init(x: 32, y: 248), .init(x: 62, y: 132), .init(x: 77, y: 91),
      .init(x: 127, y: 79),
    ]
    var path = Path()
    path.addLines(points.map { CGPoint(x: $0.x * rect.width / 300, y: $0.y * rect.height / 400) })
    path.closeSubpath()
    return path
  }
}
