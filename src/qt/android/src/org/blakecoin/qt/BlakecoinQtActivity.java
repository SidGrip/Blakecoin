package org.blakecoin.qt;

import android.os.Bundle;
import android.system.ErrnoException;
import android.system.Os;

import org.qtproject.qt5.android.bindings.QtActivity;

import java.io.File;

public class BlakecoinQtActivity extends QtActivity
{
    @Override
    public void onCreate(Bundle savedInstanceState)
    {
        final File blakecoinDir = new File(getFilesDir().getAbsolutePath() + "/.blakecoin");
        if (!blakecoinDir.exists()) {
            blakecoinDir.mkdir();
        }

        super.onCreate(savedInstanceState);
    }
}
