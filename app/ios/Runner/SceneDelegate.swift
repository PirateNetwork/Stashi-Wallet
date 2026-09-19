import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func sceneWillEnterForeground(_ scene: UIScene) {
        super.sceneWillEnterForeground(scene)
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}
