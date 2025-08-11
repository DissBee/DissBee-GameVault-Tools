import sys
import os
import json
import requests
from pathlib import Path
from requests.auth import HTTPBasicAuth
from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QLabel, QLineEdit,
    QPushButton, QFileDialog, QMessageBox, QProgressBar,
    QScrollArea, QGridLayout, QFrame, QHBoxLayout, QListWidget, QListWidgetItem
)
from PyQt6.QtCore import Qt, QTimer

CONFIG_PATH = Path(__file__).parent / "gamevault_lister_python_config.json"


class GameVaultClient(QWidget):
    def __init__(self):
        super().__init__()
        self.token = None
        self.server = ""
        self.download_dir = None

        self.games = []
        self.current_page = 1
        self.loading_page = False
        self.all_pages_loaded = False

        self.setWindowTitle("GameVault Downloader")
        self.setGeometry(200, 200, 600, 700)

        main_layout = QVBoxLayout(self)

        # Server field
        self.server_input = QLineEdit()
        self.server_input.setPlaceholderText("Server URL (e.g., http://localhost:8080)")
        main_layout.addWidget(QLabel("Server Address:"))
        main_layout.addWidget(self.server_input)

        # Username
        self.username_input = QLineEdit()
        self.username_input.setPlaceholderText("Username")
        main_layout.addWidget(QLabel("Username:"))
        main_layout.addWidget(self.username_input)

        # Password
        self.password_input = QLineEdit()
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.password_input.setPlaceholderText("Password")
        main_layout.addWidget(QLabel("Password:"))
        main_layout.addWidget(self.password_input)

        # Auth button
        self.auth_button = QPushButton("Authenticate")
        self.auth_button.clicked.connect(self.authenticate)
        main_layout.addWidget(self.auth_button)

        # Download location display + change button
        dl_layout = QHBoxLayout()
        self.download_label = QLabel("Download folder: Not set")
        self.change_dl_button = QPushButton("Change Download Folder")
        self.change_dl_button.clicked.connect(self.change_download_folder)
        self.change_dl_button.setEnabled(False)  # Disabled until login success
        dl_layout.addWidget(self.download_label)
        dl_layout.addWidget(self.change_dl_button)
        main_layout.addLayout(dl_layout)

        # Game list widget (titles only)
        self.game_list = QListWidget()
        self.game_list.itemSelectionChanged.connect(self.game_selected)
        main_layout.addWidget(self.game_list, stretch=1)

        # Progress bar
        self.progress_bar = QProgressBar()
        self.progress_bar.setValue(0)
        main_layout.addWidget(self.progress_bar)

        # Download button
        self.download_button = QPushButton("Download Selected Game")
        self.download_button.setEnabled(False)
        self.download_button.clicked.connect(self.download_selected_game)
        main_layout.addWidget(self.download_button)

        # Load config if present
        self.load_config()

        # Setup scroll event for lazy loading
        self.game_list.verticalScrollBar().valueChanged.connect(self.check_scroll_bottom)

    def load_config(self):
        if CONFIG_PATH.is_file():
            try:
                with open(CONFIG_PATH, "r") as f:
                    config = json.load(f)
                self.download_dir = config.get("download_dir")
                self.server_input.setText(config.get("server", ""))
                self.username_input.setText(config.get("username", ""))
                if self.download_dir:
                    self.download_label.setText(f"Download folder: {self.download_dir}")
                    self.change_dl_button.setEnabled(False)
            except Exception:
                pass

    def save_config(self):
        config = {
            "download_dir": self.download_dir,
            "server": self.server_input.text().strip(),
            "username": self.username_input.text().strip(),
        }
        try:
            with open(CONFIG_PATH, "w") as f:
                json.dump(config, f)
        except Exception as e:
            print(f"Warning: failed to save config: {e}")

    def authenticate(self):
        self.server = self.server_input.text().rstrip("/")
        username = self.username_input.text().strip()
        password = self.password_input.text().strip()

        if not (self.server and username and password):
            QMessageBox.warning(self, "Error", "Please fill all login fields.")
            return

        try:
            url = f"{self.server}/api/auth/basic/login"
            resp = requests.get(url, auth=HTTPBasicAuth(username, password),
                                headers={"accept": "application/json"})
            resp.raise_for_status()
            data = resp.json()
            self.token = data.get("access_token")
            if not self.token:
                raise ValueError("No access_token received from server.")

            self.save_config()

            QMessageBox.information(self, "Success", "Authenticated successfully!")

            if not self.download_dir:
                self.prompt_for_download_folder()
            else:
                self.download_label.setText(f"Download folder: {self.download_dir}")
                self.change_dl_button.setEnabled(True)
                self.reset_and_load_games()

        except Exception as e:
            QMessageBox.critical(self, "Auth Failed", str(e))

    def prompt_for_download_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Download Directory")
        if folder:
            self.download_dir = folder
            self.download_label.setText(f"Download folder: {folder}")
            self.change_dl_button.setEnabled(True)
            self.save_config()
            self.reset_and_load_games()
        else:
            QMessageBox.warning(self, "Download folder required",
                                "You must select a download folder to proceed.")

    def change_download_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Download Directory")
        if folder:
            self.download_dir = folder
            self.download_label.setText(f"Download folder: {folder}")
            self.save_config()

    def reset_and_load_games(self):
        self.games = []
        self.current_page = 1
        self.all_pages_loaded = False
        self.game_list.clear()
        self.load_games_page(self.current_page)

    def load_games_page(self, page):
        if self.loading_page or self.all_pages_loaded or not self.token:
            return
        self.loading_page = True
        try:
            url = f"{self.server}/api/games?page={page}&sortBy=title%3AASC"
            resp = requests.get(url, headers={"Authorization": f"Bearer {self.token}"})
            resp.raise_for_status()
            new_games = resp.json().get("data", [])

            if not new_games:
                self.all_pages_loaded = True
                return

            self.games.extend(new_games)
            for game in new_games:
                title = game.get("title", "Unknown")
                item = QListWidgetItem(title)
                item.setData(Qt.ItemDataRole.UserRole, game)
                self.game_list.addItem(item)

            self.current_page += 1

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Failed to load games: {e}")
        finally:
            self.loading_page = False

    def check_scroll_bottom(self, value):
        scrollbar = self.game_list.verticalScrollBar()
        if not scrollbar.isVisible():
            return
        if value >= scrollbar.maximum() - 10:  # Near bottom, adjust threshold as needed
            self.load_games_page(self.current_page)

    def game_selected(self):
        selected_items = self.game_list.selectedItems()
        if selected_items:
            self.download_button.setEnabled(True)
        else:
            self.download_button.setEnabled(False)

    def download_selected_game(self):
        if not self.download_dir:
            QMessageBox.warning(self, "Error", "Download folder is not set.")
            return
        selected_items = self.game_list.selectedItems()
        if not selected_items:
            QMessageBox.warning(self, "Error", "Please select a game to download.")
            return
        game = selected_items[0].data(Qt.ItemDataRole.UserRole)
        game_id = game.get("id")

        try:
            resp = requests.get(f"{self.server}/api/games/{game_id}/download",
                                headers={"Authorization": f"Bearer {self.token}"},
                                stream=True)
            resp.raise_for_status()

            filename = resp.headers.get("Content-Disposition", f"game_{game_id}.bin")
            if "filename=" in filename:
                filename = filename.split("filename=")[-1].strip('"')
            else:
                filename = f"game_{game_id}.bin"

            filepath = os.path.join(self.download_dir, filename)

            total_size = int(resp.headers.get("Content-Length", 0))
            downloaded_size = 0

            with open(filepath, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded_size += len(chunk)
                        if total_size > 0:
                            percent = int((downloaded_size / total_size) * 100)
                            self.progress_bar.setValue(percent)

            self.progress_bar.setValue(100)
            QMessageBox.information(self, "Success", f"Downloaded {filename}")

        except Exception as e:
            QMessageBox.critical(self, "Download Failed", str(e))


if __name__ == "__main__":
    app = QApplication(sys.argv)
    win = GameVaultClient()
    win.show()
    sys.exit(app.exec())
