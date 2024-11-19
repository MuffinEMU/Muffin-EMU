package info.cemu.cemu.emulation

import android.content.Context
import android.text.Editable
import android.text.InputFilter
import android.text.Spanned
import android.text.TextWatcher
import android.util.AttributeSet
import android.view.inputmethod.EditorInfo
import com.google.android.material.R
import com.google.android.material.textfield.TextInputEditText
import info.cemu.cemu.nativeinterface.NativeSwkbd
import java.util.regex.Pattern

class EmulationTextInputEditText @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = R.attr.editTextStyle,
) :
    TextInputEditText(context, attrs, defStyleAttr) {
    fun appendFilter(inputFilter: InputFilter) {
        filters += inputFilter
    }

    fun updateText(text: String?) {
        val hasFocus = hasFocus()
        if (hasFocus) {
            clearFocus()
        }
        setText(text)
        if (hasFocus) {
            requestFocus()
        }
    }

    fun interface OnTextChangedListener {
        fun onTextChanged(text: CharSequence)
    }


    private var onTextChangedListener: OnTextChangedListener? = null

    init {
        appendFilter { source: CharSequence, _: Int, _: Int, _: Spanned?, _: Int, _: Int ->
            if (INPUT_PATTERN.matcher(source).matches()) {
                return@appendFilter null
            }
            ""
        }
        inputType = EditorInfo.TYPE_CLASS_TEXT or EditorInfo.TYPE_TEXT_VARIATION_NORMAL
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence, start: Int, count: Int, after: Int) {
            }

            override fun onTextChanged(text: CharSequence, start: Int, before: Int, count: Int) {
                if (!hasFocus()) {
                    return
                }
                if (onTextChangedListener != null) {
                    onTextChangedListener!!.onTextChanged(text)
                }
                NativeSwkbd.onTextChanged(text.toString())
            }

            override fun afterTextChanged(s: Editable) {
            }
        })
    }

    override fun onEditorAction(actionCode: Int) {
        val text = text
        if (actionCode == EditorInfo.IME_ACTION_DONE && !text.isNullOrEmpty()) {
            onFinishedEdit()
        }
        super.onEditorAction(actionCode)
    }

    fun onFinishedEdit() {
        NativeSwkbd.onFinishedInputEdit()
    }

    fun setOnTextChangedListener(onTextChangedListener: OnTextChangedListener) {
        this.onTextChangedListener = onTextChangedListener
    }

    companion object {
        private val INPUT_PATTERN: Pattern =
            Pattern.compile("^[\\da-zA-Z \\-/;:',.?!#\\[\\]$%^&*()_@\\\\<>+=]+$")
    }
}
