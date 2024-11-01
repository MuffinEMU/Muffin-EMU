package info.cemu.Cemu.settings.input;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;
import androidx.appcompat.app.ActionBar;
import androidx.appcompat.app.AppCompatActivity;
import androidx.fragment.app.Fragment;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import java.util.List;
import java.util.Map;
import java.util.function.Function;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.LayoutGenericRecyclerViewBinding;
import info.cemu.Cemu.guibasecomponents.GenericRecyclerViewAdapter;
import info.cemu.Cemu.guibasecomponents.HeaderRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.ToggleRecyclerViewItem;
import info.cemu.Cemu.input.InputManager;
import info.cemu.Cemu.nativeinterface.NativeInput;

public class ControllerInputsFragment extends Fragment {
    public static final String CONTROLLER_INDEX = "ControllerIndex";
    private int controllerIndex;
    private int controllerType = NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED;
    private final InputManager inputManager = new InputManager();
    private final GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();
    private final EmulatedControllerTypeAdapter emulatedControllerTypeAdapter = new EmulatedControllerTypeAdapter();
    private Function<Integer, Integer> buttonIdToStringResourceIdFunction;

    private void onTypeChanged(int controllerType) {
        if (this.controllerType == controllerType) {
            return;
        }
        this.controllerType = controllerType;
        NativeInput.setControllerType(controllerIndex, controllerType);
        genericRecyclerViewAdapter.clearRecyclerViewItems();
        setControllerInputs();
    }

    private void addHeader(@StringRes int resId) {
        genericRecyclerViewAdapter.addRecyclerViewItem(new HeaderRecyclerViewItem(resId));
    }

    private void onInputPressed(InputRecyclerViewItem inputItem, int buttonId, @StringRes int buttonResourceIdName) {
        var inputDialog = new MaterialAlertDialogBuilder(requireContext()).setTitle(R.string.inputBindingDialogTitle)
                .setMessage(getString(R.string.inputBindingDialogMessage, getString(buttonResourceIdName)))
                .setNeutralButton(getString(R.string.clear), (dialogInterface, i) -> {
                    NativeInput.clearControllerMapping(controllerIndex, buttonId);
                    inputItem.clearBoundInput();
                    dialogInterface.dismiss();
                })
                .setNegativeButton(getString(R.string.cancel), (dialogInterface, i) -> dialogInterface.dismiss())
                .show();
        TextView messageTextView = inputDialog.requireViewById(android.R.id.message);
        messageTextView.setFocusableInTouchMode(true);
        messageTextView.requestFocus();
        messageTextView.setOnKeyListener((v, keyCode, event) -> {
            if (inputManager.mapKeyEventToMappingId(controllerIndex, buttonId, event)) {
                inputItem.setBoundInput(NativeInput.getControllerMapping(controllerIndex, buttonId));
                inputDialog.dismiss();
            }
            return true;
        });
        messageTextView.setOnGenericMotionListener((v, event) -> {
            if (inputManager.mapMotionEventToMappingId(controllerIndex, buttonId, event)) {
                inputItem.setBoundInput(NativeInput.getControllerMapping(controllerIndex, buttonId));
                inputDialog.dismiss();
            }
            return true;
        });
    }

    private void addInput(int buttonId, @StringRes int buttonResourceIdName, String boundInput) {
        InputRecyclerViewItem inputRecyclerViewItem = new InputRecyclerViewItem(
                buttonResourceIdName,
                boundInput,
                inputItem -> onInputPressed(inputItem, buttonId, buttonResourceIdName)
        );
        genericRecyclerViewAdapter.addRecyclerViewItem(inputRecyclerViewItem);
    }

    void addControllerInputsGroup(@StringRes int groupTextResourceId, List<Integer> buttonIds, Map<Integer, String> boundInputsMap) {
        addHeader(groupTextResourceId);
        for (var buttonId : buttonIds) {
            addInput(buttonId, buttonIdToStringResourceIdFunction.apply(buttonId), boundInputsMap.getOrDefault(buttonId, ""));
        }
    }

    private void setControllerInputs() {
        emulatedControllerTypeAdapter.setSelectedValue(controllerType);
        emulatedControllerTypeAdapter.setControllerTypeCounts(NativeInput.getVPADControllersCount(), NativeInput.getWPADControllersCount());
        String controllerTypeName = getString(ControllerTypeResourceNameMapper.controllerTypeToResourceNameId(controllerType));
        buttonIdToStringResourceIdFunction = getButtonIdToStringResIdFn(controllerType);

        SingleSelectionRecyclerViewItem<Integer> emulatedControllerSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.emulated_controller_label),
                getString(R.string.emulated_controller_selection_description, controllerTypeName),
                emulatedControllerTypeAdapter,
                (controllerType, selectionRecyclerViewItem) -> onTypeChanged(controllerType));
        genericRecyclerViewAdapter.addRecyclerViewItem(emulatedControllerSelection);
        switch (controllerType) {
            case NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> configureVPADInputs();
            case NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> configureProInputs();
            case NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> configureClassicInputs();
            case NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> configureWiimoteInputs();
        }
    }

    void configureVPADInputs() {
        Map<Integer, String> boundInputsMap = NativeInput.getControllerMappings(controllerIndex);
        addControllerInputsGroup(
                R.string.buttons,
                List.of(NativeInput.VPAD_BUTTON_A,
                        NativeInput.VPAD_BUTTON_B,
                        NativeInput.VPAD_BUTTON_X,
                        NativeInput.VPAD_BUTTON_Y,
                        NativeInput.VPAD_BUTTON_L,
                        NativeInput.VPAD_BUTTON_R,
                        NativeInput.VPAD_BUTTON_ZL,
                        NativeInput.VPAD_BUTTON_ZR,
                        NativeInput.VPAD_BUTTON_PLUS,
                        NativeInput.VPAD_BUTTON_MINUS),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.d_pad,
                List.of(NativeInput.VPAD_BUTTON_UP,
                        NativeInput.VPAD_BUTTON_DOWN,
                        NativeInput.VPAD_BUTTON_LEFT,
                        NativeInput.VPAD_BUTTON_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.left_axis,
                List.of(NativeInput.VPAD_BUTTON_STICKL,
                        NativeInput.VPAD_BUTTON_STICKL_UP,
                        NativeInput.VPAD_BUTTON_STICKL_DOWN,
                        NativeInput.VPAD_BUTTON_STICKL_LEFT,
                        NativeInput.VPAD_BUTTON_STICKL_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.right_axis,
                List.of(NativeInput.VPAD_BUTTON_STICKR,
                        NativeInput.VPAD_BUTTON_STICKR_UP,
                        NativeInput.VPAD_BUTTON_STICKR_DOWN,
                        NativeInput.VPAD_BUTTON_STICKR_LEFT,
                        NativeInput.VPAD_BUTTON_STICKR_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.extra,
                List.of(NativeInput.VPAD_BUTTON_MIC,
                        NativeInput.VPAD_BUTTON_HOME,
                        NativeInput.VPAD_BUTTON_SCREEN),
                boundInputsMap
        );
        ToggleRecyclerViewItem toggleShowScreen = new ToggleRecyclerViewItem(
                getString(R.string.toggle_screen),
                getString(R.string.toggle_screen_description),
                NativeInput.getVPADScreenToggle(controllerIndex),
                toggle -> NativeInput.setVPADScreenToggle(controllerIndex, toggle)
        );
        genericRecyclerViewAdapter.addRecyclerViewItem(toggleShowScreen);
    }

    void configureProInputs() {
        Map<Integer, String> boundInputsMap = NativeInput.getControllerMappings(controllerIndex);
        addControllerInputsGroup(
                R.string.buttons,
                List.of(NativeInput.PRO_BUTTON_A,
                        NativeInput.PRO_BUTTON_B,
                        NativeInput.PRO_BUTTON_X,
                        NativeInput.PRO_BUTTON_Y,
                        NativeInput.PRO_BUTTON_L,
                        NativeInput.PRO_BUTTON_R,
                        NativeInput.PRO_BUTTON_ZL,
                        NativeInput.PRO_BUTTON_ZR,
                        NativeInput.PRO_BUTTON_PLUS,
                        NativeInput.PRO_BUTTON_MINUS,
                        NativeInput.PRO_BUTTON_HOME),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.left_axis,
                List.of(NativeInput.PRO_BUTTON_STICKL,
                        NativeInput.PRO_BUTTON_STICKL_UP,
                        NativeInput.PRO_BUTTON_STICKL_DOWN,
                        NativeInput.PRO_BUTTON_STICKL_LEFT,
                        NativeInput.PRO_BUTTON_STICKL_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.right_axis,
                List.of(NativeInput.PRO_BUTTON_STICKR,
                        NativeInput.PRO_BUTTON_STICKR_UP,
                        NativeInput.PRO_BUTTON_STICKR_DOWN,
                        NativeInput.PRO_BUTTON_STICKR_LEFT,
                        NativeInput.PRO_BUTTON_STICKR_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.d_pad,
                List.of(NativeInput.PRO_BUTTON_UP,
                        NativeInput.PRO_BUTTON_DOWN,
                        NativeInput.PRO_BUTTON_LEFT,
                        NativeInput.PRO_BUTTON_RIGHT),
                boundInputsMap
        );
    }

    void configureClassicInputs() {
        Map<Integer, String> boundInputsMap = NativeInput.getControllerMappings(controllerIndex);
        addControllerInputsGroup(
                R.string.buttons,
                List.of(NativeInput.CLASSIC_BUTTON_A,
                        NativeInput.CLASSIC_BUTTON_B,
                        NativeInput.CLASSIC_BUTTON_X,
                        NativeInput.CLASSIC_BUTTON_Y,
                        NativeInput.CLASSIC_BUTTON_L,
                        NativeInput.CLASSIC_BUTTON_R,
                        NativeInput.CLASSIC_BUTTON_ZL,
                        NativeInput.CLASSIC_BUTTON_ZR,
                        NativeInput.CLASSIC_BUTTON_PLUS,
                        NativeInput.CLASSIC_BUTTON_MINUS,
                        NativeInput.CLASSIC_BUTTON_HOME),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.left_axis,
                List.of(NativeInput.CLASSIC_BUTTON_STICKL_UP,
                        NativeInput.CLASSIC_BUTTON_STICKL_DOWN,
                        NativeInput.CLASSIC_BUTTON_STICKL_LEFT,
                        NativeInput.CLASSIC_BUTTON_STICKL_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.right_axis,
                List.of(NativeInput.CLASSIC_BUTTON_STICKR_UP,
                        NativeInput.CLASSIC_BUTTON_STICKR_DOWN,
                        NativeInput.CLASSIC_BUTTON_STICKR_LEFT,
                        NativeInput.CLASSIC_BUTTON_STICKR_RIGHT),
                boundInputsMap
        );
        addControllerInputsGroup(
                R.string.d_pad,
                List.of(NativeInput.CLASSIC_BUTTON_UP,
                        NativeInput.CLASSIC_BUTTON_DOWN,
                        NativeInput.CLASSIC_BUTTON_LEFT,
                        NativeInput.CLASSIC_BUTTON_RIGHT),
                boundInputsMap
        );
    }

    void configureWiimoteInputs() {
        Map<Integer, String> boundInputsMap = NativeInput.getControllerMappings(controllerIndex);
        addControllerInputsGroup(
                R.string.buttons,
                List.of(NativeInput.WIIMOTE_BUTTON_A,
                        NativeInput.WIIMOTE_BUTTON_B,
                        NativeInput.WIIMOTE_BUTTON_1,
                        NativeInput.WIIMOTE_BUTTON_2,
                        NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z,
                        NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C,
                        NativeInput.WIIMOTE_BUTTON_PLUS,
                        NativeInput.WIIMOTE_BUTTON_MINUS,
                        NativeInput.WIIMOTE_BUTTON_HOME),
                boundInputsMap);
        addControllerInputsGroup(
                R.string.d_pad,
                List.of(NativeInput.WIIMOTE_BUTTON_UP,
                        NativeInput.WIIMOTE_BUTTON_DOWN,
                        NativeInput.WIIMOTE_BUTTON_LEFT,
                        NativeInput.WIIMOTE_BUTTON_RIGHT),
                boundInputsMap);
        addControllerInputsGroup(
                R.string.nunchuck,
                List.of(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP,
                        NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN,
                        NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT,
                        NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT),
                boundInputsMap);
    }

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container, @Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        controllerIndex = requireArguments().getInt(CONTROLLER_INDEX);
        ActionBar actionBar = ((AppCompatActivity) requireActivity()).getSupportActionBar();
        if (actionBar != null) {
            actionBar.setTitle(getString(R.string.controller_numbered, controllerIndex + 1));
        }
        if (!NativeInput.isControllerDisabled(controllerIndex)) {
            controllerType = NativeInput.getControllerType(controllerIndex);
        }
        setControllerInputs();

        var binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false);
        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);
        return binding.getRoot();
    }

    private Function<Integer, Integer> getButtonIdToStringResIdFn(int controllerType) {
        return switch (controllerType) {
            case NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> this::getButtonVPADResourceIdName;
            case NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> this::getButtonProControllerResourceIdName;
            case NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> this::getButtonClassicControllerResourceIdName;
            case NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> this::getButtonWiimoteResourceIdName;
            case NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED -> null;
            default -> throw new IllegalArgumentException("Invalid controllerType " + controllerType);
        };
    }

    private int getButtonVPADResourceIdName(int buttonId) {
        return switch (buttonId) {
            case NativeInput.VPAD_BUTTON_A -> R.string.button_a;
            case NativeInput.VPAD_BUTTON_B -> R.string.button_b;
            case NativeInput.VPAD_BUTTON_X -> R.string.button_x;
            case NativeInput.VPAD_BUTTON_Y -> R.string.button_y;
            case NativeInput.VPAD_BUTTON_L -> R.string.button_l;
            case NativeInput.VPAD_BUTTON_R -> R.string.button_r;
            case NativeInput.VPAD_BUTTON_ZL -> R.string.button_zl;
            case NativeInput.VPAD_BUTTON_ZR -> R.string.button_zr;
            case NativeInput.VPAD_BUTTON_PLUS -> R.string.button_plus;
            case NativeInput.VPAD_BUTTON_MINUS -> R.string.button_minus;
            case NativeInput.VPAD_BUTTON_UP -> R.string.button_up;
            case NativeInput.VPAD_BUTTON_DOWN -> R.string.button_down;
            case NativeInput.VPAD_BUTTON_LEFT -> R.string.button_left;
            case NativeInput.VPAD_BUTTON_RIGHT -> R.string.button_right;
            case NativeInput.VPAD_BUTTON_STICKL -> R.string.button_stickl;
            case NativeInput.VPAD_BUTTON_STICKR -> R.string.button_stickr;
            case NativeInput.VPAD_BUTTON_STICKL_UP -> R.string.button_stickl_up;
            case NativeInput.VPAD_BUTTON_STICKL_DOWN -> R.string.button_stickl_down;
            case NativeInput.VPAD_BUTTON_STICKL_LEFT -> R.string.button_stickl_left;
            case NativeInput.VPAD_BUTTON_STICKL_RIGHT -> R.string.button_stickl_right;
            case NativeInput.VPAD_BUTTON_STICKR_UP -> R.string.button_stickr_up;
            case NativeInput.VPAD_BUTTON_STICKR_DOWN -> R.string.button_stickr_down;
            case NativeInput.VPAD_BUTTON_STICKR_LEFT -> R.string.button_stickr_left;
            case NativeInput.VPAD_BUTTON_STICKR_RIGHT -> R.string.button_stickr_right;
            case NativeInput.VPAD_BUTTON_MIC -> R.string.button_mic;
            case NativeInput.VPAD_BUTTON_SCREEN -> R.string.button_screen;
            case NativeInput.VPAD_BUTTON_HOME -> R.string.button_home;
            default -> throw new IllegalArgumentException("Invalid buttonId " + buttonId + " for VPAD controller type");
        };
    }

    private int getButtonProControllerResourceIdName(int buttonId) {
        return switch (buttonId) {
            case NativeInput.PRO_BUTTON_A -> R.string.button_a;
            case NativeInput.PRO_BUTTON_B -> R.string.button_b;
            case NativeInput.PRO_BUTTON_X -> R.string.button_x;
            case NativeInput.PRO_BUTTON_Y -> R.string.button_y;
            case NativeInput.PRO_BUTTON_L -> R.string.button_l;
            case NativeInput.PRO_BUTTON_R -> R.string.button_r;
            case NativeInput.PRO_BUTTON_ZL -> R.string.button_zl;
            case NativeInput.PRO_BUTTON_ZR -> R.string.button_zr;
            case NativeInput.PRO_BUTTON_PLUS -> R.string.button_plus;
            case NativeInput.PRO_BUTTON_MINUS -> R.string.button_minus;
            case NativeInput.PRO_BUTTON_HOME -> R.string.button_home;
            case NativeInput.PRO_BUTTON_UP -> R.string.button_up;
            case NativeInput.PRO_BUTTON_DOWN -> R.string.button_down;
            case NativeInput.PRO_BUTTON_LEFT -> R.string.button_left;
            case NativeInput.PRO_BUTTON_RIGHT -> R.string.button_right;
            case NativeInput.PRO_BUTTON_STICKL -> R.string.button_stickl;
            case NativeInput.PRO_BUTTON_STICKR -> R.string.button_stickr;
            case NativeInput.PRO_BUTTON_STICKL_UP -> R.string.button_stickl_up;
            case NativeInput.PRO_BUTTON_STICKL_DOWN -> R.string.button_stickl_down;
            case NativeInput.PRO_BUTTON_STICKL_LEFT -> R.string.button_stickl_left;
            case NativeInput.PRO_BUTTON_STICKL_RIGHT -> R.string.button_stickl_right;
            case NativeInput.PRO_BUTTON_STICKR_UP -> R.string.button_stickr_up;
            case NativeInput.PRO_BUTTON_STICKR_DOWN -> R.string.button_stickr_down;
            case NativeInput.PRO_BUTTON_STICKR_LEFT -> R.string.button_stickr_left;
            case NativeInput.PRO_BUTTON_STICKR_RIGHT -> R.string.button_stickr_right;
            default -> throw new IllegalArgumentException("Invalid buttonId " + buttonId + " for Pro controller type");
        };
    }

    private int getButtonClassicControllerResourceIdName(int buttonId) {
        return switch (buttonId) {
            case NativeInput.CLASSIC_BUTTON_A -> R.string.button_a;
            case NativeInput.CLASSIC_BUTTON_B -> R.string.button_b;
            case NativeInput.CLASSIC_BUTTON_X -> R.string.button_x;
            case NativeInput.CLASSIC_BUTTON_Y -> R.string.button_y;
            case NativeInput.CLASSIC_BUTTON_L -> R.string.button_l;
            case NativeInput.CLASSIC_BUTTON_R -> R.string.button_r;
            case NativeInput.CLASSIC_BUTTON_ZL -> R.string.button_zl;
            case NativeInput.CLASSIC_BUTTON_ZR -> R.string.button_zr;
            case NativeInput.CLASSIC_BUTTON_PLUS -> R.string.button_plus;
            case NativeInput.CLASSIC_BUTTON_MINUS -> R.string.button_minus;
            case NativeInput.CLASSIC_BUTTON_HOME -> R.string.button_home;
            case NativeInput.CLASSIC_BUTTON_UP -> R.string.button_up;
            case NativeInput.CLASSIC_BUTTON_DOWN -> R.string.button_down;
            case NativeInput.CLASSIC_BUTTON_LEFT -> R.string.button_left;
            case NativeInput.CLASSIC_BUTTON_RIGHT -> R.string.button_right;
            case NativeInput.CLASSIC_BUTTON_STICKL_UP -> R.string.button_stickl_up;
            case NativeInput.CLASSIC_BUTTON_STICKL_DOWN -> R.string.button_stickl_down;
            case NativeInput.CLASSIC_BUTTON_STICKL_LEFT -> R.string.button_stickl_left;
            case NativeInput.CLASSIC_BUTTON_STICKL_RIGHT -> R.string.button_stickl_right;
            case NativeInput.CLASSIC_BUTTON_STICKR_UP -> R.string.button_stickr_up;
            case NativeInput.CLASSIC_BUTTON_STICKR_DOWN -> R.string.button_stickr_down;
            case NativeInput.CLASSIC_BUTTON_STICKR_LEFT -> R.string.button_stickr_left;
            case NativeInput.CLASSIC_BUTTON_STICKR_RIGHT -> R.string.button_stickr_right;
            default -> throw new IllegalArgumentException("Invalid buttonId " + buttonId + " for Classic controller type");
        };
    }

    private int getButtonWiimoteResourceIdName(int buttonId) {
        return switch (buttonId) {
            case NativeInput.WIIMOTE_BUTTON_A -> R.string.button_a;
            case NativeInput.WIIMOTE_BUTTON_B -> R.string.button_b;
            case NativeInput.WIIMOTE_BUTTON_1 -> R.string.button_1;
            case NativeInput.WIIMOTE_BUTTON_2 -> R.string.button_2;
            case NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z -> R.string.button_nunchuck_z;
            case NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C -> R.string.button_nunchuck_c;
            case NativeInput.WIIMOTE_BUTTON_PLUS -> R.string.button_plus;
            case NativeInput.WIIMOTE_BUTTON_MINUS -> R.string.button_minus;
            case NativeInput.WIIMOTE_BUTTON_UP -> R.string.button_up;
            case NativeInput.WIIMOTE_BUTTON_DOWN -> R.string.button_down;
            case NativeInput.WIIMOTE_BUTTON_LEFT -> R.string.button_left;
            case NativeInput.WIIMOTE_BUTTON_RIGHT -> R.string.button_right;
            case NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP -> R.string.button_nunchuck_up;
            case NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN -> R.string.button_nunchuck_down;
            case NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT -> R.string.button_nunchuck_left;
            case NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT -> R.string.button_nunchuck_right;
            case NativeInput.WIIMOTE_BUTTON_HOME -> R.string.button_home;
            default -> throw new IllegalArgumentException("Invalid buttonId " + buttonId + " for Wiimote controller type");
        };
    }
}