package ai.clomni.messenger.sample;

import android.content.Context;

import java.util.HashMap;
import java.util.Map;

import ai.clomni.messenger.Clomni;
import ai.clomni.messenger.ClomniLogLevel;
import ai.clomni.messenger.ClomniPush;
import ai.clomni.messenger.ClomniThemeMode;
import ai.clomni.messenger.ClomniUser;
import ai.clomni.messenger.UnreadCountListener;

/**
 * The SDK from Java: every call of the facade, compiled with the sample, so the API stays usable from Java
 * (static methods, overloads for the optional arguments, listeners as lambdas). Not called by the sample's screens.
 */
final class JavaUsage {
    private JavaUsage() {
    }

    static void everything(Context context, Map<String, String> pushData) {
        Clomni.initialize(context, "app_demo", "android_sdk-demo");
        Clomni.setLogLevel(ClomniLogLevel.DEBUG);
        Clomni.loginUser(new ClomniUser("12345", "aysel@example.com"), "hash from the app's server");
        Clomni.loginUnidentifiedUser();
        Clomni.updateUser("Aysel Məmmədova");

        Clomni.present();
        Clomni.present("profile_support");
        Clomni.presentNewConversation();
        Clomni.presentConversation("conv_5521");
        Clomni.dismiss();

        Map<String, Object> data = new HashMap<>();
        data.put("ride_id", "R-1923");
        Clomni.startFlow("ride_problem", data, true);

        Clomni.setLauncherVisible(true);
        Clomni.setBottomPadding(64);
        Clomni.setTheme("#0A66C2", null, ClomniThemeMode.DARK);

        Clomni.setDeviceToken("fcm-token");
        Clomni.setNotificationIcon(android.R.drawable.stat_notify_chat);
        if (ClomniPush.isClomniPush(pushData)) {
            ClomniPush.handle(context, pushData);
        }

        UnreadCountListener badge = count -> { };
        Clomni.addUnreadCountListener(badge);
        Clomni.removeUnreadCountListener(badge);
        Clomni.onMessengerOpened(source -> { });
        Clomni.onMessengerClosed(() -> { });
        Clomni.onConversationStarted(id -> { });
        Clomni.onUnreadCountChanged(count -> { });
        Clomni.onFlowCompleted(flowId -> { });
        Clomni.onLink(url -> false);
        String version = Clomni.getVersion();

        Clomni.logout();
    }
}
