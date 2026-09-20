import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/sms_service.dart';

void main() {
  group('Strict Client-Side SMS Pre-Filtering', () {
    test('Allows legitimate Saudi bank senders', () {
      expect(SmsService.isAllowedSender('SNB'), isTrue);
      expect(SmsService.isAllowedSender('AlRajhi'), isTrue);
      expect(SmsService.isAllowedSender('ALINMA'), isTrue);
      expect(SmsService.isAllowedSender('RIYAD'), isTrue);
      expect(SmsService.isAllowedSender('SAB'), isTrue);
      expect(SmsService.isAllowedSender('920000000'), isTrue);
    });

    test('Rejects non-bank senders', () {
      expect(SmsService.isAllowedSender('STC'), isFalse);
      expect(SmsService.isAllowedSender('Uber'), isFalse);
      expect(SmsService.isAllowedSender('Amazon'), isFalse);
      expect(SmsService.isAllowedSender('Unknown'), isFalse);
    });

    test('Detects and drops OTP / verification messages', () {
      // English OTPs
      expect(SmsService.isOtpMessage('Your OTP is 482910 for login.'), isTrue);
      expect(SmsService.isOtpMessage('Your verification code is 8839.'), isTrue);
      expect(SmsService.isOtpMessage('Use code 123456 to verify.'), isTrue);

      // Arabic OTPs
      expect(SmsService.isOtpMessage('رمز التحقق الخاص بك هو 938201'), isTrue);
      expect(SmsService.isOtpMessage('لا تشارك رمز التأكيد مع أي شخص'), isTrue);
      expect(SmsService.isOtpMessage('رمز الدخول لمرة واحدة هو 7748'), isTrue);
      expect(SmsService.isOtpMessage('يرجى تأكيد عملية تحقق الحساب'), isTrue);
    });

    test('Allows real bank debit / transaction messages', () {
      // Arabic debit
      expect(
        SmsService.isOtpMessage(
          'تم خصم ٤٥٠٫٠٠ ريال من حسابك لدى تميمي للأسواق رقم العملية 123456',
        ),
        isFalse,
      );

      // English debit SNB
      expect(
        SmsService.isOtpMessage(
          'SNB: Purchase of SAR 89.00 at STARBUCKS COFFEE approved. Available balance: SAR 5,421.00',
        ),
        isFalse,
      );

      // English debit Al Rajhi
      expect(
        SmsService.isOtpMessage(
          'Al Rajhi Bank: SAR 1,250.75 was debited from your account for purchase at JARIR BOOKSTORE. Ref: 789012',
        ),
        isFalse,
      );
    });
  });
}
