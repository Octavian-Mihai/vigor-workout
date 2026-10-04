import SwiftUI
import PhotosUI

struct AddMeasurementView: View {
    var existing: BodyMeasurementEntry?
    var onSave: (BodyMeasurementEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("lengthUnit") private var lengthUnitRaw = LengthUnit.cm.rawValue

    @State private var date = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var removePhoto = false
    @FocusState private var keyboardFocused: Bool

    @State private var includeWeight = false
    @State private var weightValue: Double = 80
    @State private var includeCalories = false
    @State private var caloriesValue = 2000

    @State private var includeHeight = false
    @State private var heightValue: Double = 175

    @State private var includeNeck = false
    @State private var neckValue: Double = 38
    @State private var includeShoulders = false
    @State private var shouldersValue: Double = 115
    @State private var includeChest = false
    @State private var chestValue: Double = 100

    @State private var includeLeftBiceps = false
    @State private var leftBicepsValue: Double = 35
    @State private var includeRightBiceps = false
    @State private var rightBicepsValue: Double = 35
    @State private var includeLeftForearm = false
    @State private var leftForearmValue: Double = 28
    @State private var includeRightForearm = false
    @State private var rightForearmValue: Double = 28

    @State private var includeWaist = false
    @State private var waistValue: Double = 80
    @State private var includeHips = false
    @State private var hipsValue: Double = 95

    @State private var includeLeftThigh = false
    @State private var leftThighValue: Double = 55
    @State private var includeRightThigh = false
    @State private var rightThighValue: Double = 55
    @State private var includeLeftCalf = false
    @State private var leftCalfValue: Double = 38
    @State private var includeRightCalf = false
    @State private var rightCalfValue: Double = 38

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var lengthUnit: LengthUnit { LengthUnit(rawValue: lengthUnitRaw) ?? .cm }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section("Photo") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack {
                        if let pendingPhotoData, let image = UIImage(data: pendingPhotoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else if let existing, let filename = existing.photoFilename, !removePhoto {
                            ProgressPhotoThumbnail(filename: filename, size: 72)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, height: 72)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Text(pendingPhotoData != nil || (existing?.photoFilename != nil && !removePhoto) ? "Change photo" : "Add progress photo")
                        Spacer()
                    }
                }
                if existing?.photoFilename != nil || pendingPhotoData != nil {
                    Button("Remove photo", role: .destructive) {
                        photoItem = nil
                        pendingPhotoData = nil
                        removePhoto = true
                    }
                }
            }

            Section("Weight & intake") {
                measurementToggle("Body weight", isOn: $includeWeight, unit: weightUnit.rawValue) {
                    TextField("Weight", value: $weightValue, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($keyboardFocused)
                .focused($keyboardFocused)
                }
                measurementToggle("Calorie intake", isOn: $includeCalories, unit: "kcal") {
                    TextField("Calories", value: $caloriesValue, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($keyboardFocused)
                .focused($keyboardFocused)
                }
            }

            Section("Height") {
                measurementToggle("Height", isOn: $includeHeight, unit: lengthUnit.title) {
                    TextField("Height", value: $heightValue, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($keyboardFocused)
                .focused($keyboardFocused)
                }
            }

            Section("Upper body") {
                circumferenceField("Neck", isOn: $includeNeck, value: $neckValue)
                circumferenceField("Shoulders", isOn: $includeShoulders, value: $shouldersValue)
                circumferenceField("Chest", isOn: $includeChest, value: $chestValue)
            }

            Section("Arms") {
                circumferenceField("Left biceps", isOn: $includeLeftBiceps, value: $leftBicepsValue)
                circumferenceField("Right biceps", isOn: $includeRightBiceps, value: $rightBicepsValue)
                circumferenceField("Left forearm", isOn: $includeLeftForearm, value: $leftForearmValue)
                circumferenceField("Right forearm", isOn: $includeRightForearm, value: $rightForearmValue)
            }

            Section("Core") {
                circumferenceField("Waist", isOn: $includeWaist, value: $waistValue)
                circumferenceField("Hips", isOn: $includeHips, value: $hipsValue)
            }

            Section("Legs") {
                circumferenceField("Left thigh", isOn: $includeLeftThigh, value: $leftThighValue)
                circumferenceField("Right thigh", isOn: $includeRightThigh, value: $rightThighValue)
                circumferenceField("Left calf", isOn: $includeLeftCalf, value: $leftCalfValue)
                circumferenceField("Right calf", isOn: $includeRightCalf, value: $rightCalfValue)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(existing == nil ? "Add measurement" : "Edit measurement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardFocused = false }
            }
        }
        .onAppear { loadExisting() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        pendingPhotoData = data
                        removePhoto = false
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        includeWeight || includeCalories || includeHeight
            || includeNeck || includeShoulders || includeChest
            || includeLeftBiceps || includeRightBiceps || includeLeftForearm || includeRightForearm
            || includeWaist || includeHips
            || includeLeftThigh || includeRightThigh || includeLeftCalf || includeRightCalf
            || pendingPhotoData != nil
            || (existing?.photoFilename != nil && !removePhoto)
    }

    @ViewBuilder
    private func measurementToggle<Content: View>(
        _ label: String,
        isOn: Binding<Bool>,
        unit: String,
        @ViewBuilder field: () -> Content
    ) -> some View {
        Toggle(label, isOn: isOn)
        if isOn.wrappedValue {
            HStack {
                Text("Value (\(unit))")
                Spacer()
                field()
                    .frame(width: 100)
            }
        }
    }

    @ViewBuilder
    private func circumferenceField(_ label: String, isOn: Binding<Bool>, value: Binding<Double>) -> some View {
        measurementToggle(label, isOn: isOn, unit: lengthUnit.title) {
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($keyboardFocused)
        }
    }

    private func loadExisting() {
        guard let existing else { return }
        date = existing.date
        if let kg = existing.kilograms {
            includeWeight = true
            weightValue = weightUnit.fromKg(kg)
        }
        if let kcal = existing.caloriesKcal {
            includeCalories = true
            caloriesValue = kcal
        }
        if let cm = existing.heightCm {
            includeHeight = true
            heightValue = lengthUnit.fromCm(cm)
        }
        loadCircumference(existing.neckCm, toggle: &includeNeck, value: &neckValue)
        loadCircumference(existing.shouldersCm, toggle: &includeShoulders, value: &shouldersValue)
        loadCircumference(existing.chestCm, toggle: &includeChest, value: &chestValue)
        loadCircumference(existing.leftBicepsCm, toggle: &includeLeftBiceps, value: &leftBicepsValue)
        loadCircumference(existing.rightBicepsCm, toggle: &includeRightBiceps, value: &rightBicepsValue)
        loadCircumference(existing.leftForearmCm, toggle: &includeLeftForearm, value: &leftForearmValue)
        loadCircumference(existing.rightForearmCm, toggle: &includeRightForearm, value: &rightForearmValue)
        loadCircumference(existing.waistCm, toggle: &includeWaist, value: &waistValue)
        loadCircumference(existing.hipsCm, toggle: &includeHips, value: &hipsValue)
        loadCircumference(existing.leftThighCm, toggle: &includeLeftThigh, value: &leftThighValue)
        loadCircumference(existing.rightThighCm, toggle: &includeRightThigh, value: &rightThighValue)
        loadCircumference(existing.leftCalfCm, toggle: &includeLeftCalf, value: &leftCalfValue)
        loadCircumference(existing.rightCalfCm, toggle: &includeRightCalf, value: &rightCalfValue)
    }

    private func loadCircumference(_ cm: Double?, toggle: inout Bool, value: inout Double) {
        guard let cm else { return }
        toggle = true
        value = lengthUnit.fromCm(cm)
    }

    private func save() {
        let entry = existing ?? BodyMeasurementEntry(date: date)
        entry.date = date
        entry.kilograms = includeWeight ? weightUnit.toKg(weightValue) : nil
        entry.caloriesKcal = includeCalories ? caloriesValue : nil
        entry.heightCm = includeHeight ? lengthUnit.toCm(heightValue) : nil
        entry.neckCm = includeNeck ? lengthUnit.toCm(neckValue) : nil
        entry.shouldersCm = includeShoulders ? lengthUnit.toCm(shouldersValue) : nil
        entry.chestCm = includeChest ? lengthUnit.toCm(chestValue) : nil
        entry.leftBicepsCm = includeLeftBiceps ? lengthUnit.toCm(leftBicepsValue) : nil
        entry.rightBicepsCm = includeRightBiceps ? lengthUnit.toCm(rightBicepsValue) : nil
        entry.leftForearmCm = includeLeftForearm ? lengthUnit.toCm(leftForearmValue) : nil
        entry.rightForearmCm = includeRightForearm ? lengthUnit.toCm(rightForearmValue) : nil
        entry.waistCm = includeWaist ? lengthUnit.toCm(waistValue) : nil
        entry.hipsCm = includeHips ? lengthUnit.toCm(hipsValue) : nil
        entry.leftThighCm = includeLeftThigh ? lengthUnit.toCm(leftThighValue) : nil
        entry.rightThighCm = includeRightThigh ? lengthUnit.toCm(rightThighValue) : nil
        entry.leftCalfCm = includeLeftCalf ? lengthUnit.toCm(leftCalfValue) : nil
        entry.rightCalfCm = includeRightCalf ? lengthUnit.toCm(rightCalfValue) : nil

        if removePhoto {
            ProgressPhotoStorage.delete(filename: entry.photoFilename)
            entry.photoFilename = nil
        }
        if let pendingPhotoData {
            ProgressPhotoStorage.delete(filename: entry.photoFilename)
            if let filename = try? ProgressPhotoStorage.saveJPEG(pendingPhotoData) {
                entry.photoFilename = filename
            }
        }

        onSave(entry)
        dismiss()
    }
}
