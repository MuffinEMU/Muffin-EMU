package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.slider.LabelFormatter
import com.google.android.material.slider.Slider
import info.cemu.cemu.R

class SliderRecyclerViewItem(
    private val label: String,
    private val valueFrom: Float,
    private val valueTo: Float,
    private var currentValue: Float,
    private val stepSize: Float,
    private val onChangeListener: OnChangeListener?,
    private val labelFormatter: LabelFormatter?
) :
    RecyclerViewItem {
    fun interface OnChangeListener {
        fun onChange(value: Float)
    }

    private class SliderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var label: TextView =
            itemView.findViewById(R.id.slider_label)
        var slider: Slider = itemView.findViewById(R.id.slider)
    }

    constructor(
        label: String,
        valueFrom: Float,
        valueTo: Float,
        currentValue: Float,
        onChangeListener: OnChangeListener?,
        labelFormatter: LabelFormatter?
    ) : this(
        label,
        valueFrom,
        valueTo,
        currentValue,
        DEFAULT_STEP_SIZE,
        onChangeListener,
        labelFormatter
    )

    constructor(
        label: String,
        valueFrom: Float,
        valueTo: Float,
        currentValue: Float,
        onChangeListener: OnChangeListener?
    ) : this(label, valueFrom, valueTo, currentValue, DEFAULT_STEP_SIZE, onChangeListener, null)

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return SliderViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.layout_slider, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val sliderViewHolder = viewHolder as SliderViewHolder
        sliderViewHolder.label.text = label
        if (labelFormatter != null) {
            sliderViewHolder.slider.setLabelFormatter(labelFormatter)
        }
        sliderViewHolder.slider.valueFrom = valueFrom
        sliderViewHolder.slider.valueTo = valueTo
        sliderViewHolder.slider.stepSize = stepSize
        sliderViewHolder.slider.value = currentValue
        sliderViewHolder.slider.addOnChangeListener(Slider.OnChangeListener { slider: Slider?, value: Float, fromUser: Boolean ->
            currentValue = value
            onChangeListener?.onChange(currentValue)
        })
    }

    companion object {
        private const val DEFAULT_STEP_SIZE = 1.0f
    }
}
