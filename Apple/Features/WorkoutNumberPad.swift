import FitnessTrackerCore
import SwiftUI

struct WorkoutNumberPad: View {
  @Environment(\.locale) private var locale
  @ScaledMetric(relativeTo: .title2) private var keyHeight: CGFloat = 48
  let model: WorkoutNumberPadModel
  let workout: Workout

  var body: some View {
    VStack(spacing: 0) {
      if let error = model.error {
        Text(L10n.text(error, locale: locale)).font(.footnote).foregroundStyle(.red).padding(8)
          .accessibilityIdentifier("numberPadError")
      } else if let count = model.copiedRows {
        Text(L10n.format("Обновлено строк: %@", String(count), locale: locale)).font(.footnote)
          .foregroundStyle(.secondary).padding(8).accessibilityIdentifier("numberPadFeedback")
      }
      HStack(alignment: .top, spacing: 0) {
        VStack(spacing: 0) {
          ForEach(0..<3) { row in
            HStack(spacing: 0) {
              ForEach(1..<4) { column in
                digit(row * 3 + column)
                if column < 3 { verticalSeparator }
              }
            }
            Divider()
          }
          HStack(spacing: 0) {
            Button {
              model.decimal()
            } label: {
              Text(model.decimalSeparator).frame(maxWidth: .infinity, minHeight: keyHeight)
                .contentShape(.rect)
            }
            .disabled(model.field?.isWeight != true)
            .opacity(model.field?.isWeight == true ? 1 : 0.35)
            .keyboardShortcut(KeyEquivalent(model.decimalSeparator.first ?? "."), modifiers: [])
            .accessibilityLabel(L10n.text("Десятичный разделитель", locale: locale))
            .accessibilityIdentifier("numberPadDecimal")
            verticalSeparator
            digit(0)
            verticalSeparator
            Button {
              model.delete()
            } label: {
              Image(systemName: "delete.left").frame(maxWidth: .infinity, minHeight: keyHeight)
                .contentShape(.rect)
            }
            .buttonRepeatBehavior(.enabled).accessibilityLabel(
              L10n.text("Удалить цифру", locale: locale)
            )
            .accessibilityIdentifier("numberPadDelete")
            .keyboardShortcut(.delete, modifiers: [])
          }
        }.frame(maxWidth: .infinity).foregroundStyle(.primary)
        VStack(spacing: 0) {
          Button {
            model.advance(in: workout)
          } label: {
            Image(systemName: "chevron.right").frame(maxWidth: .infinity, minHeight: keyHeight)
              .contentShape(.rect)
          }.accessibilityLabel(L10n.text("Следующее поле", locale: locale)).accessibilityIdentifier(
            "numberPadNext"
          )
          .keyboardShortcut(.return, modifiers: [])
          Button {
            model.copyDown(in: workout)
          } label: {
            HStack(spacing: 0) {
              Image(systemName: "arrow.down")
              Image(systemName: "equal").font(.body)
            }
            .frame(maxWidth: .infinity, minHeight: keyHeight * 1.5)
            .contentShape(.rect)
          }.disabled(!model.canCopy(in: workout))
            .opacity(model.canCopy(in: workout) ? 1 : 0.35)
            .accessibilityLabel(
              L10n.text(
                model.field?.isWeight == true
                  ? "Повторить вес в следующих обычных подходах"
                  : "Повторить число повторений в следующих строках", locale: locale)
            )
            .accessibilityIdentifier("numberPadCopyDown")
          Button {
            model.dismiss()
          } label: {
            Image(systemName: "keyboard.chevron.compact.down").frame(
              maxWidth: .infinity, minHeight: keyHeight * 1.5
            )
            .contentShape(.rect)
          }.accessibilityLabel(L10n.text("Скрыть цифровую панель", locale: locale))
            .accessibilityIdentifier("numberPadHide")
            .keyboardShortcut(.escape, modifiers: [])
        }.frame(width: keyHeight * 1.1).foregroundStyle(FitTheme.accent).background(FitTheme.card)
      }
      .font(.title2).monospacedDigit().buttonStyle(.plain)
      .frame(maxWidth: 600)
    }
    .frame(maxWidth: .infinity).background(FitTheme.grouped.ignoresSafeArea(edges: .bottom))
    .overlay(alignment: .top) { Divider() }
    .accessibilityIdentifier("workoutNumberPad")
  }
  private func digit(_ number: Int) -> some View {
    Button {
      model.digit(number)
    } label: {
      Text(String(number)).frame(maxWidth: .infinity, minHeight: keyHeight).contentShape(.rect)
    }
    .accessibilityIdentifier("numberPadDigit_\(number)")
    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [])
  }
  private var verticalSeparator: some View {
    Rectangle().fill(FitTheme.separator).frame(width: 0.5, height: keyHeight).accessibilityHidden(
      true)
  }
}
