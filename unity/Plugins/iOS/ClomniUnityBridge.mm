// UnitySendMessage is declared in Unity's UnityInterface.h, which Swift in the UnityFramework target cannot import:
// a framework has no bridging header. This file hands ClomniUnityBridge.swift a pointer to it.

extern "C" {

void UnitySendMessage(const char* obj, const char* method, const char* msg);
void clomni_unity_set_sender(const char* receiver, void (*send)(const char*, const char*, const char*));

void clomni_unity_install(const char* receiver)
{
    clomni_unity_set_sender(receiver, UnitySendMessage);
}

}
