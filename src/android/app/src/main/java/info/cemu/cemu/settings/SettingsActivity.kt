package info.cemu.cemu.settings

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.AppBarConfiguration
import androidx.navigation.ui.AppBarConfiguration.Builder
import androidx.navigation.ui.AppBarConfiguration.OnNavigateUpListener
import androidx.navigation.ui.NavigationUI.setupWithNavController
import info.cemu.cemu.R
import info.cemu.cemu.databinding.ActivitySettingsBinding
import java.util.Objects

class SettingsActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivitySettingsBinding.inflate(
            layoutInflater
        )
        setContentView(binding.root)
        setSupportActionBar(binding.toolbarSettings)
        val navHostFragment =
            supportFragmentManager.findFragmentById(R.id.nav_host_fragment_content_settings) as NavHostFragment?
        val navController = navHostFragment!!.navController
        val appBarConfiguration: AppBarConfiguration = Builder()
            .setFallbackOnNavigateUpListener(OnNavigateUpListener { this.onSupportNavigateUp() })
            .build()
        setupWithNavController(binding.toolbarSettings, navController, appBarConfiguration)
    }
}