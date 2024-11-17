package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import com.google.android.material.radiobutton.MaterialRadioButton
import info.cemu.cemu.R

abstract class BaseSelectionAdapter<T> : BaseAdapter() {
    @JvmField
    protected var selectedPosition: Int = 0

    open fun setSelectedValue(selectedValue: T) {
        selectedPosition = getPositionOf(selectedValue)
    }

    abstract fun getPositionOf(value: T): Int

    protected abstract fun setRadioButtonText(radioButton: MaterialRadioButton, position: Int)

    abstract override fun getItem(position: Int): T

    override fun getItemId(position: Int): Long {
        return position.toLong()
    }

    override fun getView(position: Int, view: View?, viewGroup: ViewGroup): View {
        return (view ?: LayoutInflater.from(viewGroup.context)
            .inflate(R.layout.layout_single_selection_item, viewGroup, false))
            .apply {
                val radioButton =
                    findViewById<MaterialRadioButton>(R.id.single_selection_item_radio_button)
                radioButton.isEnabled = isEnabled(position)
                setRadioButtonText(radioButton, position)
                radioButton.isChecked = position == selectedPosition
            }
    }
}
