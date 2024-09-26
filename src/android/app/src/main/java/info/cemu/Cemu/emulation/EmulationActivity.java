package info.cemu.Cemu.emulation;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.MotionEvent;

import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.lifecycle.Observer;
import androidx.lifecycle.ViewModelProvider;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.ActivityEmulationBinding;
import info.cemu.Cemu.input.InputManager;

public class EmulationActivity extends AppCompatActivity implements Observer<EmulationData> {
    private EmulationViewModel viewModel;
    private boolean hasEmulationError;
    public static final String LAUNCH_PATH = "LAUNCH_PATH";
    private ActivityEmulationBinding binding;
    private EmulationFragment emulationFragment;
    private final InputManager inputManager = new InputManager();

    @Override
    public boolean onGenericMotionEvent(MotionEvent event) {
        if (inputManager.onMotionEvent(event))
            return true;
        return super.onGenericMotionEvent(event);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (inputManager.onKeyEvent(event))
            return true;
        return super.dispatchKeyEvent(event);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                showExitConfirmationDialog();
            }
        });

        viewModel = new ViewModelProvider(this).get(EmulationViewModel.class);
        viewModel.getEmulationData().observe(this, this);
        Intent intent = getIntent();
        Bundle extras = intent.getExtras();
        Uri data = intent.getData();
        String launchPath = null;
        if (extras != null) {
            launchPath = extras.getString(LAUNCH_PATH);
        }
        if (launchPath == null && data != null) {
            launchPath = data.toString();
        }
        if (launchPath == null) {
            throw new RuntimeException("launchPath is null");
        }
        setFullscreen();
        binding = ActivityEmulationBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());
        emulationFragment = (EmulationFragment) getSupportFragmentManager().findFragmentById(R.id.emulation_frame);
        if (emulationFragment == null) {
            emulationFragment = new EmulationFragment(launchPath);
            getSupportFragmentManager()
                    .beginTransaction()
                    .add(R.id.emulation_frame, emulationFragment)
                    .commit();
        }

    }

    private void showExitConfirmationDialog() {
        MaterialAlertDialogBuilder builder = new MaterialAlertDialogBuilder(this);
        builder.setTitle(R.string.exit_confirmation_title)
                .setMessage(R.string.exit_confirm_message)
                .setPositiveButton(R.string.yes, (dialog, which) -> quit())
                .setNegativeButton(R.string.no, (dialog, which) -> dialog.cancel())
                .create()
                .show();
    }

    private void onEmulationError(EmulationError emulationError) {
        MaterialAlertDialogBuilder builder = new MaterialAlertDialogBuilder(this);
        builder.setTitle(R.string.error)
                .setMessage(emulationError.errorMessage())
                .setNeutralButton(R.string.quit, (dialog, which) -> dialog.dismiss())
                .setOnDismissListener(dialog -> quit())
                .create()
                .show();
    }

    private void setFullscreen() {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat controller = new WindowInsetsControllerCompat(getWindow(), getWindow().getDecorView());
        controller.hide(WindowInsetsCompat.Type.systemBars());
        controller.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
    }

    private void quit() {
        finishAffinity();
        System.exit(0);
    }

    @Override
    public void onChanged(EmulationData emulationData) {
        if (emulationData.emulationError().isPresent() && !hasEmulationError) {
            hasEmulationError = true;
            onEmulationError(emulationData.emulationError().get());
        }
    }
}