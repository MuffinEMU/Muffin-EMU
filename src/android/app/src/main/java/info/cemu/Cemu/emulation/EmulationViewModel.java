package info.cemu.Cemu.emulation;

import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import androidx.lifecycle.ViewModel;

import java.util.Optional;

public class EmulationViewModel extends ViewModel {
    private final MutableLiveData<EmulationData> emulationData = new MutableLiveData<>(new EmulationData(Optional.empty()));

    public void setEmulationError(EmulationError emulationError) {
        emulationData.setValue(new EmulationData(Optional.of(emulationError)));
    }

    public LiveData<EmulationData> getEmulationData() {
        return emulationData;
    }
}
