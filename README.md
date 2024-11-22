
# Smart Mauzo

**Scan & Sell** is a Flutter-based mobile application designed to simplify inventory and sales management. The app allows users to scan items, track sales, and manage their profile, all with an intuitive interface and seamless navigation.

---

## Features

- **Scan Items**: Easily scan barcodes to add or manage inventory.
- **Track Sales**: Monitor sales records and analyze trends.
- **Profile Management**: Update user details and manage preferences.
- **Supabase Integration**: Securely store and retrieve data using Supabase.
- **Dynamic Navigation**: Intuitive navigation using a bottom navigation bar.

---

## Screens

1. **Scan Screen**:  
   Scan barcodes or QR codes for inventory management.

2. **Sales Screen**:  
   View and manage sales data.

3. **Profile Screen**:  
   Manage user profile and settings.

---

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase
- **State Management**: `setState` (with plans for scalability)
- **Design**: Material 3 (Modern UI components)

---

## Getting Started

### Prerequisites

- **Flutter SDK**: Ensure you have Flutter installed. [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Supabase Account**: Set up a free account at [Supabase](https://supabase.com).
- **Dart**: Make sure Dart is configured with Flutter.

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/jimmyurl/smart-mauzo.git
   cd smart-mauzo
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Set up Supabase:
   - Add your Supabase URL and API key in a secure file (e.g., `lib/services/supabase_service.dart`).

4. Declare assets in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/icons/
   ```

5. Run the app:
   ```bash
   flutter run
   ```

---

## Folder Structure

```plaintext
smart-mauzo/
│
├── lib/
│   ├── screens/
│   │   ├── scan_screen.dart       # Scan screen UI
│   │   ├── sales_screen.dart      # Sales screen UI
│   │   └── profile_screen.dart    # Profile screen UI
│   ├── services/
│   │   └── supabase_service.dart  # Supabase initialization
│   └── main.dart                  # Main entry point
├── assets/
│   └── icons/                     # App icons (e.g., scan.png, sales.png, profile.png)
├── pubspec.yaml                   # Project dependencies
└── README.md                      # Project documentation
```

---

## Dependencies

- **Flutter**: UI framework
- **Supabase**: Backend as a Service
- **Material Design 3**: Modern design principles

Install all dependencies using:
```bash
flutter pub get
```

---

## Future Enhancements

- Add analytics for sales trends.
- Implement user authentication.
- Enable real-time inventory updates.
- Add multi-language support.

---

## Contributing

1. Fork the repository.
2. Create your feature branch:
   ```bash
   git checkout -b feature-name
   ```
3. Commit your changes:
   ```bash
   git commit -m "Add your message here"
   ```
4. Push to the branch:
   ```bash
   git push origin feature-name
   ```
5. Open a pull request.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## Contact

For support or inquiries:
- **Email**: jimmy.james365@gmail.com
- **GitHub**: [jimmyurl](https://github.com/jimmyurl)
