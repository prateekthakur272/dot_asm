/// Descriptors of the modal dialogs. `state.modal = ModalSettings()` shows one; `buildActiveModal` resolves each
/// case with an exhaustive pattern match.
sealed class AppModal {
  const AppModal();
}

class ModalSettings extends AppModal {
  const ModalSettings();
}

class ModalAbout extends AppModal {
  const ModalAbout();
}

class ModalDeveloper extends AppModal {
  const ModalDeveloper();
}

class ModalUpdateAvailable extends AppModal {
  const ModalUpdateAvailable(this.version);
  final String version;
}
