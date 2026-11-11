import FitLifeCore
import SwiftUI
import UIKit

private enum WorkoutSetTableLayout {
  static let indexWidth: CGFloat = 44
  static let spacing: CGFloat = 6
  static let horizontalPadding: CGFloat = 2
}

struct WorkoutSetTableHeader: View {
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  let unit: WeightUnit
  var notesExpanded = false
  @ScaledMetric(relativeTo: .caption) private var expandedNoteWidth: CGFloat = 84
  private var noteColumnWidth: CGFloat { notesExpanded ? min(expandedNoteWidth, 112) : 44 }

  var body: some View {
    if !typeSize.isAccessibilitySize {
      HStack(spacing: WorkoutSetTableLayout.spacing) {
        Color.clear.frame(width: WorkoutSetTableLayout.indexWidth, height: 1)
        HStack(spacing: WorkoutSetTableLayout.spacing) {
          Text(L10n.format("Вес, %@", L10n.text(unit.rawValue, locale: locale), locale: locale))
            .frame(maxWidth: .infinity)
          Text(L10n.text("Повт.", locale: locale)).lineLimit(1).frame(maxWidth: .infinity)
          Text(L10n.text("Заметка", locale: locale)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(width: noteColumnWidth)
        }.frame(maxWidth: .infinity)
      }
      .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      .padding(.horizontal, WorkoutSetTableLayout.horizontalPadding)
      .accessibilityHidden(true)
      .accessibilityIdentifier("workoutSetTableHeader")
    }
  }
}

struct WorkoutSetRow<ContextActions: View>: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .caption) private var expandedNoteWidth: CGFloat = 84
  @ScaledMetric(relativeTo: .body) private var inputWidth: CGFloat = 76
  private var noteColumnWidth: CGFloat { notesExpanded ? min(expandedNoteWidth, 112) : 44 }
  let set: WorkoutSet
  let index: Int
  var marker: String? = nil
  let unit: WeightUnit
  var notesExpanded = false
  let editable: Bool
  var showsDropMetadata = true
  var canCorrectCompleted = false
  let selected: Bool
  let weight: String
  let repetitions: String
  let numberPad: WorkoutNumberPadModel
  let edit: (WorkoutSetField) -> Void
  let select: () -> Void
  let advance: () -> Void
  let editCompleted: () -> Void
  var openNote: (() -> Void)? = nil
  @ViewBuilder let contextActions: () -> ContextActions

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: WorkoutSetTableLayout.spacing) {
        VStack(spacing: 0) {
          Group {
            if editable {
              Button(action: select) { indexLabel }.buttonStyle(.plain)
            } else {
              indexLabel
            }
          }
          .accessibilityLabel(
            L10n.format(
              marker == nil ? "Подход %@" : "Снижение веса %@", String(index + 1), locale: locale)
          )
          .accessibilityAddTraits(selected ? .isSelected : [])
          .accessibilityValue(
            L10n.text(set.completedAt != nil ? "Подход выполнен" : "Не выполнено", locale: locale))
        }.frame(width: WorkoutSetTableLayout.indexWidth)
          .accessibilityIdentifier("setIndex_\(set.id)")
          .contextMenu { contextActions() }
        Group {
          if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(
                  L10n.format("Вес, %@", L10n.text(unit.rawValue, locale: locale), locale: locale)
                )
                .font(.caption).foregroundStyle(.secondary)
                weightField
              }
              VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Повторения", locale: locale)).font(.caption)
                  .foregroundStyle(.secondary)
                repetitionsField
              }
            }
          } else {
            HStack(spacing: WorkoutSetTableLayout.spacing) {
              weightField
              repetitionsField
              noteField.frame(width: noteColumnWidth)
            }
          }
        }.frame(maxWidth: .infinity)
        if typeSize.isAccessibilitySize { noteField.frame(width: noteColumnWidth) }
      }
      if set.isWarmup || (showsDropMetadata && set.isDropSet) || (set.loadMultiplier ?? 1) > 1 {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { metadata }
          VStack(alignment: .leading, spacing: 6) { metadata }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.leading, WorkoutSetTableLayout.indexWidth + WorkoutSetTableLayout.spacing)
        .contentShape(.rect).contextMenu { contextActions() }
      }
    }
    .padding(.horizontal, WorkoutSetTableLayout.horizontalPadding)
    .padding(.vertical, typeSize.isAccessibilitySize ? 16 : 8)
    .background(
      selected && set.completedAt == nil ? colorTheme.accent.opacity(0.09) : Color.clear,
      in: .rect(cornerRadius: 16)
    )
    .accessibilityElement(children: .contain)
  }

  private var noteField: some View {
    Group {
      if let openNote, set.note != nil || editable || canCorrectCompleted {
        Button(action: openNote) {
          Group {
            if let note = set.note, !note.isEmpty {
              Text(note.replacingOccurrences(of: "\n", with: " "))
                .font(.caption.weight(selected ? .semibold : .regular)).lineLimit(2).truncationMode(
                  .tail)
            } else {
              Image(systemName: "square.and.pencil").font(.caption)
            }
          }
          .frame(
            maxWidth: .infinity, minHeight: 44, alignment: set.note == nil ? .center : .leading
          )
          .contentShape(.rect)
        }.buttonStyle(.plain).foregroundStyle(
          selected ? colorTheme.accent : set.completedAt != nil ? .primary : .secondary
        )
        .accessibilityLabel(
          L10n.text(
            set.note == nil ? "Добавить заметку к подходу" : "Заметка к подходу", locale: locale)
        )
        .accessibilityValue(set.note ?? "")
        .accessibilityIdentifier("setNote_\(set.id)")
      } else {
        Color.clear.frame(maxWidth: .infinity, minHeight: 44).accessibilityHidden(true)
      }
    }
  }

  private var indexLabel: some View {
    Text(marker ?? String(index + 1))
      .font(.callout.weight(selected ? .bold : set.completedAt != nil ? .semibold : .regular))
      .monospacedDigit()
      .foregroundStyle(
        selected ? colorTheme.accent : set.completedAt != nil ? Color.primary : FitTheme.muted
      )
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(.rect)
  }

  @ViewBuilder private var metadata: some View {
    if set.isWarmup {
      Label(L10n.text("Разминка", locale: locale), systemImage: "flame")
        .foregroundStyle(colorTheme.accent).padding(.horizontal, 8).padding(.vertical, 4)
        .background(colorTheme.accent.opacity(0.1), in: .capsule).accessibilityIdentifier(
          "warmupSet")
    }
    if showsDropMetadata && set.isDropSet {
      Text(L10n.format("Дропсет · этапов: %@", String(set.stages.count), locale: locale))
        .foregroundStyle(colorTheme.accent).padding(.horizontal, 8).padding(.vertical, 4)
        .background(colorTheme.accent.opacity(0.1), in: .capsule)
    }
    if let multiplier = set.loadMultiplier, multiplier > 1 {
      Text(L10n.format("Множитель веса: %@", String(multiplier), locale: locale))
    }
  }

  private var weightField: some View {
    Group {
      if editable {
        valueButton(weight, field: .weight(set.id))
          .accessibilityIdentifier("setWeight_\(set.id)")
          .accessibilityLabel(
            L10n.format("Вес в %@", L10n.text(unit.rawValue, locale: locale), locale: locale))
      } else if canCorrectCompleted && set.completedAt != nil {
        Button(action: editCompleted) {
          Text(formattedWeight).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain).accessibilityLabel(
          L10n.format("Вес в %@", L10n.text(unit.rawValue, locale: locale), locale: locale)
        )
        .accessibilityHint(L10n.text("Изменить выполненный подход", locale: locale))
        .accessibilityValue(formattedWeight)
        .accessibilityIdentifier("correctSetWeight_\(set.id)")
      } else {
        Text(formattedWeight).frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityLabel(
            L10n.format(
              "Вес: %@ %@", formattedWeight, L10n.text(unit.rawValue, locale: locale),
              locale: locale))
      }
    }
    .font(.body.weight(selected ? .semibold : .regular))
    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
    .foregroundStyle(selected ? colorTheme.accent : set.completedAt != nil ? .primary : .secondary)
  }

  private var formattedWeight: String {
    if set.completedAt == nil { return weight.isEmpty ? "—" : weight }
    return unit.display(set.weightKG).formatted(
      .number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))
  }

  private var repetitionsField: some View {
    Group {
      if editable {
        valueButton(repetitions, field: .repetitions(set.id))
          .accessibilityIdentifier("setRepetitions_\(set.id)")
          .accessibilityLabel(L10n.text("Повторения", locale: locale))
      } else if canCorrectCompleted && set.completedAt != nil {
        Button(action: editCompleted) {
          Text(String(set.repetitions)).frame(maxWidth: .infinity, minHeight: 44).contentShape(
            .rect)
        }
        .buttonStyle(.plain).accessibilityLabel(L10n.text("Повторения", locale: locale))
        .accessibilityHint(L10n.text("Изменить выполненный подход", locale: locale))
        .accessibilityValue(String(set.repetitions))
        .accessibilityIdentifier("correctSetRepetitions_\(set.id)")
      } else {
        Text(formattedRepetitions)
          .frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityLabel(
            L10n.format(
              "Повторения: %@", formattedRepetitions, locale: locale
            ))
      }
    }
    .font(.body.weight(selected ? .semibold : .regular))
    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
    .foregroundStyle(selected ? colorTheme.accent : set.completedAt != nil ? .primary : .secondary)
  }

  private var formattedRepetitions: String {
    if set.completedAt == nil { return repetitions.isEmpty ? "—" : repetitions }
    return String(set.repetitions)
  }

  private func valueButton(_ value: String, field: WorkoutSetField) -> some View {
    let active = numberPad.field == field
    return HStack(spacing: 0) {
      Spacer(minLength: 0)
      WorkoutNumericField(
        value: value, field: field, numberPad: numberPad,
        tint: UIColor(colorTheme.accent),
        foreground: selected ? UIColor(colorTheme.accent) : active ? .label : .secondaryLabel,
        fontWeight: selected ? .semibold : active ? .medium : .regular,
        begin: { edit(field) }, advance: advance
      )
      .frame(
        maxWidth: typeSize.isAccessibilitySize ? .infinity : min(inputWidth, 100), minHeight: 44
      )
      .layoutPriority(1)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .accessibilityHint(L10n.text("Открыть цифровую панель", locale: locale))
  }
}

/// UITextField provides native caret/selection while inputView suppresses the system keyboard;
/// the existing safe-area number pad remains the only onscreen keyboard.
private struct WorkoutNumericField: UIViewRepresentable {
  let value: String
  let field: WorkoutSetField
  let numberPad: WorkoutNumberPadModel
  let tint: UIColor
  let foreground: UIColor
  let fontWeight: UIFont.Weight
  let begin: () -> Void
  let advance: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UITextField {
    let view = WorkoutNumberTextField()
    view.delegate = context.coordinator
    view.onActivate = { [weak coordinator = context.coordinator] in coordinator?.activate() }
    view.onSelectionInteraction = { [weak coordinator = context.coordinator] in
      coordinator?.beginSelectionInteraction()
    }
    // A completed tap activates the field; a swipe starting over it remains a list gesture.
    let touchObserver = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.activateFromTap(_:)))
    touchObserver.cancelsTouchesInView = false
    touchObserver.delaysTouchesBegan = false
    touchObserver.delaysTouchesEnded = false
    touchObserver.delegate = context.coordinator
    view.addGestureRecognizer(touchObserver)
    view.inputView = UIView(frame: .zero)
    view.inputAssistantItem.leadingBarButtonGroups = []
    view.inputAssistantItem.trailingBarButtonGroups = []
    view.textAlignment = .center
    view.placeholder = "—"
    view.autocorrectionType = .no
    view.spellCheckingType = .no
    view.smartInsertDeleteType = .no
    view.keyboardType = field.isWeight ? .decimalPad : .numberPad
    view.adjustsFontForContentSizeCategory = true
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }
  func updateUIView(_ view: UITextField, context: Context) {
    context.coordinator.parent = self
    context.coordinator.synchronize(view)
    view.font = UIFontMetrics(forTextStyle: .body).scaledFont(
      for: .systemFont(ofSize: 18, weight: fontWeight), compatibleWith: view.traitCollection)
    view.tintColor = tint
    view.textColor = foreground
    if numberPad.field == field {
      context.coordinator.focus(view)
    } else if view.isFirstResponder {
      view.resignFirstResponder()
    }
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize?
  {
    CGSize(width: proposal.width ?? 60, height: max(44, uiView.font?.lineHeight ?? 24))
  }

  @MainActor final class Coordinator: NSObject, UITextFieldDelegate, UIGestureRecognizerDelegate {
    var parent: WorkoutNumericField
    private var synchronizing = false
    init(_ parent: WorkoutNumericField) { self.parent = parent }
    func synchronize(_ view: UITextField) {
      let wasSynchronizing = synchronizing
      synchronizing = true
      defer { synchronizing = wasSynchronizing }
      let active = parent.numberPad.field == parent.field
      let text = active ? parent.numberPad.text : parent.value
      if view.text != text { view.text = text }
      guard active,
        let start = view.position(
          from: view.beginningOfDocument, offset: parent.numberPad.selection.location),
        let end = view.position(from: start, offset: parent.numberPad.selection.length)
      else { return }
      if selectedRange(in: view) != parent.numberPad.selection {
        view.selectedTextRange = view.textRange(from: start, to: end)
      }
    }
    func focus(_ view: UITextField) {
      guard view.window != nil, !view.isFirstResponder else { return }
      let wasSynchronizing = synchronizing
      synchronizing = true
      defer { synchronizing = wasSynchronizing }
      // First-responder activation can update UIKit's selection. Restore the model's
      // caret before accepting user selection changes that cancel first-input replacement.
      view.becomeFirstResponder()
      synchronize(view)
    }
    func activate() { parent.begin() }
    @objc func activateFromTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      activate()
    }
    func beginSelectionInteraction() {
      guard parent.numberPad.field == parent.field else { return }
      parent.numberPad.beginSelectionInteraction()
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
      -> Bool
    {
      if gestureRecognizer.view?.isFirstResponder == true,
        parent.numberPad.field == parent.field
      {
        beginSelectionInteraction()
      }
      return true
    }
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
      // Only explicit user activation or the number pad can choose a field. A delayed
      // UIKit focus request must never reopen a dismissed field or switch to another one.
      parent.numberPad.field == parent.field
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      guard parent.numberPad.field == parent.field else { return false }
      parent.advance()
      return false
    }
    func textFieldDidEndEditing(_ textField: UITextField) {
      if !textField.isFirstResponder, parent.numberPad.field == parent.field {
        parent.numberPad.dismiss()
      }
    }
    func textFieldDidChangeSelection(_ textField: UITextField) {
      guard !synchronizing, parent.numberPad.field == parent.field,
        let range = selectedRange(in: textField)
      else { return }
      parent.numberPad.selectText(range, userInitiated: false)
      synchronize(textField)
    }
    func textField(
      _ textField: UITextField, shouldChangeCharactersIn range: NSRange,
      replacementString string: String
    ) -> Bool {
      guard parent.numberPad.field == parent.field else { return false }
      parent.numberPad.replaceCharacters(in: range, with: string)
      synchronize(textField)
      return false
    }
    private func selectedRange(in view: UITextField) -> NSRange? {
      guard let range = view.selectedTextRange else { return nil }
      return NSRange(
        location: view.offset(from: view.beginningOfDocument, to: range.start),
        length: view.offset(from: range.start, to: range.end))
    }
  }
}

/// Native selection stays available after focus without treating UIKit's automatic caret
/// placement as a user's request to append to the displayed value.
private final class WorkoutNumberTextField: UITextField {
  var onActivate: (() -> Void)?
  var onSelectionInteraction: (() -> Void)?

  override func accessibilityActivate() -> Bool {
    onActivate?()
    return super.accessibilityActivate()
  }

  override func select(_ sender: Any?) {
    onSelectionInteraction?()
    super.select(sender)
  }

  override func selectAll(_ sender: Any?) {
    onSelectionInteraction?()
    super.selectAll(sender)
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { press in
      guard let key = press.key else { return false }
      return [
        UIKeyboardHIDUsage.keyboardLeftArrow, .keyboardRightArrow, .keyboardUpArrow,
        .keyboardDownArrow,
      ].contains(key.keyCode)
    }) {
      onSelectionInteraction?()
    }
    super.pressesBegan(presses, with: event)
  }
}
