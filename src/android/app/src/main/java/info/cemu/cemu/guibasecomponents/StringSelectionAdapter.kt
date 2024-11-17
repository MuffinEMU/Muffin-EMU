package info.cemu.cemu.guibasecomponents

import com.google.android.material.radiobutton.MaterialRadioButton
import java.util.stream.IntStream

class StringSelectionAdapter(private val choices: List<String>, selectedValue: String) :
    BaseSelectionAdapter<String>() {
    init {
        setSelectedValue(selectedValue)
    }

    override fun setSelectedValue(selectedValue: String) {
        selectedPosition = getPositionOf(selectedValue)
    }

    override fun getPositionOf(value: String): Int {
        val optionalInt =
            IntStream.range(0, choices.size).filter { position: Int -> choices[position] == value }
                .findFirst()
        if (optionalInt.isPresent) {
            return optionalInt.asInt
        }
        throw IllegalArgumentException("value $value was not found in the list of choices")
    }

    override fun setRadioButtonText(radioButton: MaterialRadioButton, position: Int) {
        radioButton.text = choices[position]
    }

    override fun getCount(): Int {
        return choices.size
    }

    override fun getItem(position: Int): String {
        return choices[position]
    }
}
