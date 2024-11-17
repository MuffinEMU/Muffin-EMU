package info.cemu.cemu.guibasecomponents

import android.widget.TextView
import com.google.android.material.radiobutton.MaterialRadioButton
import java.util.function.Consumer
import java.util.stream.IntStream

open class SelectionAdapter<T> : BaseSelectionAdapter<T> {
    class ChoiceItem<T>(val setTextForChoice: Consumer<TextView>, val choiceValue: T)

    @JvmField
    protected var choiceItems: List<ChoiceItem<T>> = ArrayList()

    constructor() : super()

    constructor(choiceItems: List<ChoiceItem<T>>, selectedValue: T) : super() {
        this.choiceItems = choiceItems
        setSelectedValue(selectedValue)
    }

    final override fun setSelectedValue(selectedValue: T) {
        selectedPosition = getPositionOf(selectedValue)
    }

    override fun getPositionOf(value: T): Int {
        val optionalInt = IntStream.range(0, choiceItems.size)
            .filter { position: Int -> choiceItems[position].choiceValue == value }
            .findFirst()
        if (optionalInt.isPresent) {
            return optionalInt.asInt
        }
        throw IllegalArgumentException("value $value was not found in the list of choiceItems")
    }

    override fun setRadioButtonText(radioButton: MaterialRadioButton, position: Int) {
        choiceItems[position].setTextForChoice.accept(radioButton)
    }

    override fun getCount(): Int {
        return choiceItems.size
    }

    override fun getItem(position: Int): T {
        return choiceItems[position].choiceValue
    }
}
