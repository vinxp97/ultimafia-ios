import SwiftUI

// Bundled copies of the site's legal pages so they render natively and offline.
// Source: react_main/src/pages/Policy/PrivacyPolicy.jsx (Last Updated: February 21, 2026) and
//         react_main/src/pages/Policy/TermsOfService.jsx (Last Updated: February 6, 2026),
// converted JSX -> markdown (Typography h2/h3/h4 -> #/##/###, ListItemText -> "- ", <strong> -> **, Link -> [](url)).
// Email addresses are wrapped as [addr](mailto:addr) so they open Mail with To filled in.
// UPDATE NOTE: when either page's "Last Updated" date changes on the site, re-run the conversion
// (same mapping) and replace the text below verbatim. Wording is intentionally unedited.

enum UMLegalText {
    static let privacyPolicy = #"""
# Privacy Policy

Last Updated: February 21, 2026

UltiMafia ("we," "us," or "our") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our website, services, and applications (collectively, the "Service"). Please read this Privacy Policy carefully. By using the Service, you consent to the data practices described in this policy.

This Privacy Policy is designed to comply with applicable privacy laws, including the General Data Protection Regulation (GDPR) for users in the European Union, the UK GDPR for users in the United Kingdom, the California Consumer Privacy Act (CCPA) for California residents, and other applicable United States federal and state privacy laws.

## 1. Information We Collect

### 1.1 Information You Provide to Us

We collect information that you provide directly to us when you:

- Create an account (email address, username, and authentication credentials);
- Link third-party accounts (such as Discord or Google) for authentication purposes;
- Complete your profile (biographical information, pronouns, profile pictures, banners, custom emotes, and other user-generated content);
- Participate in games, forums, or other interactive features;
- Submit reports, appeals, or communicate with our moderation team;
- Contact us for support or other inquiries.

### 1.2 Automatically Collected Information

When you access or use the Service, we automatically collect certain information, including:

- Log Data: Internet Protocol (IP) addresses, browser type and version, device information, operating system, pages visited, time and date of visits, time spent on pages, and other usage statistics;
- Cookies and Similar Technologies: We use cookies, web beacons, and similar tracking technologies to collect information about your interactions with the Service. Cookies are small data files stored on your device that help us improve your experience, remember your preferences, and analyze usage patterns;
- Game Data: Information related to your participation in games, including game history, statistics, achievements, and performance data;
- Account Activity: Information about your account activity, including login history, feature usage, and interactions with other users.

### 1.3 Information from Third-Party Services

If you choose to authenticate using third-party services (such as Discord or Google), we may receive certain information from those services, including your username, email address, and profile information, in accordance with the authorization you provide and the privacy settings of those services.

## 2. How We Use Your Information

We use the information we collect for the following purposes:

- To provide, maintain, and improve the Service;
- To create and manage your account, authenticate your identity, and process your transactions;
- To communicate with you about your account, the Service, updates, and promotional materials (you may opt out of promotional communications at any time);
- To enforce our Terms of Service, Rules of Conduct, and other policies;
- To investigate and respond to reports, appeals, and other user concerns;
- To detect, prevent, and address fraud, security issues, and other harmful activities;
- To analyze usage patterns and trends to improve the Service and user experience;
- To comply with legal obligations and respond to lawful requests from government authorities;
- To protect the rights, property, or safety of UltiMafia, our users, or others.

## 3. Legal Basis for Processing (EU/UK Users)

If you are located in the European Union or United Kingdom, we process your personal data based on the following legal grounds:

- **Consent:** When you have given clear consent for us to process your personal data for specific purposes;
- **Contract Performance:** When processing is necessary for the performance of a contract with you or to take steps at your request before entering into a contract;
- **Legal Obligation:** When processing is necessary for compliance with a legal obligation;
- **Legitimate Interests:** When processing is necessary for our legitimate interests or those of a third party, such as preventing fraud, ensuring security, or improving our services, provided that your interests and fundamental rights do not override those interests.

## 4. How We Share Your Information

We do not sell your personal information. We may share your information in the following circumstances:

### 4.1 Service Providers

We may share your information with third-party service providers who perform services on our behalf, such as hosting, data storage, analytics, payment processing, email delivery, and customer support. These service providers are contractually obligated to protect your information and use it only for the purposes for which it was shared.

### 4.2 Legal Requirements

We may disclose your information if required to do so by law or in response to valid requests by public authorities (e.g., a court or government agency), or if we believe disclosure is necessary to:

- Comply with legal obligations or respond to legal process;
- Protect and defend our rights or property;
- Prevent or investigate possible wrongdoing in connection with the Service;
- Protect the personal safety of users of the Service or the public.

### 4.3 Business Transfers

If we are involved in a merger, acquisition, or asset sale, your information may be transferred as part of that transaction. We will provide notice before your information is transferred and becomes subject to a different privacy policy.

### 4.4 With Your Consent

We may share your information with your explicit consent or at your direction.

### 4.5 Public Information

Certain information you choose to make public through your profile or in public areas of the Service (such as usernames, profile pictures, and public game statistics) will be visible to other users and may be accessible through search engines or other third-party services.

## 5. Cookies and Tracking Technologies

We use cookies and similar tracking technologies to collect and store information about your preferences and activity on the Service. Cookies are small text files placed on your device when you visit our website.

**Types of Cookies We Use:**

- **Essential Cookies:** Required for the Service to function properly, including authentication and security features. These cannot be disabled;
- **Functional Cookies:** Remember your preferences and settings to enhance your experience;
- **Analytics Cookies:** Help us understand how visitors interact with the Service to improve performance and user experience.

You can control cookies through your browser settings. However, disabling certain cookies may limit your ability to use some features of the Service. For more information about cookies and how to manage them, please visit [www.allaboutcookies.org](https://www.allaboutcookies.org).

## 6. Data Security

We implement appropriate technical and organizational security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. These measures include encryption, secure servers, access controls, and regular security assessments.

However, no method of transmission over the Internet or electronic storage is 100% secure. While we strive to use commercially acceptable means to protect your information, we cannot guarantee absolute security. You are responsible for maintaining the confidentiality of your account credentials.

## 7. Data Retention

We retain your personal information for as long as necessary to fulfill the purposes outlined in this Privacy Policy, unless a longer retention period is required or permitted by law. When we no longer need your information, we will delete or anonymize it in accordance with our data retention policies.

If you delete your account, we will delete or anonymize your personal information, except where we are required to retain it for legal, regulatory, or legitimate business purposes (such as maintaining game records, resolving disputes, or enforcing our agreements).

## 8. International Data Transfers

Your information may be transferred to and processed in countries other than your country of residence. These countries may have data protection laws that differ from those in your country.

If you are located in the European Union or United Kingdom, we ensure that appropriate safeguards are in place for such transfers, including standard contractual clauses approved by the European Commission or UK authorities, or other legally recognized transfer mechanisms.

By using the Service, you consent to the transfer of your information to countries outside your country of residence.

## 9. Your Rights and Choices

Depending on your location, you may have certain rights regarding your personal information:

### 9.1 Rights for EU/UK Users (GDPR/UK GDPR)

If you are located in the European Union or United Kingdom, you have the following rights:

- **Right of Access:** Request a copy of the personal data we hold about you;
- **Right to Rectification:** Request correction of inaccurate or incomplete data;
- **Right to Erasure ("Right to be Forgotten"):** Request deletion of your personal data under certain circumstances;
- **Right to Restrict Processing:** Request restriction of processing of your personal data;
- **Right to Data Portability:** Receive your personal data in a structured, commonly used, and machine-readable format;
- **Right to Object:** Object to processing of your personal data based on legitimate interests;
- **Right to Withdraw Consent:** Withdraw consent where processing is based on consent.

To exercise these rights, please contact us using the information provided in Section 14. We will respond to your request within one month, though this period may be extended by two additional months for complex requests.

### 9.2 Rights for California Residents (CCPA)

If you are a California resident, you have the following rights under the California Consumer Privacy Act:

- **Right to Know:** Request information about the categories and specific pieces of personal information we collect, use, disclose, or sell;
- **Right to Delete:** Request deletion of your personal information, subject to certain exceptions;
- **Right to Opt-Out:** Opt out of the sale of personal information (we do not sell personal information);
- **Right to Non-Discrimination:** We will not discriminate against you for exercising your privacy rights.

To exercise these rights, please contact us using the information provided in Section 14. We will verify your identity before processing your request.

### 9.3 Account Settings

You can access and update certain information through your account settings on the Service. You may also request deletion of your account, which will result in the deletion of your personal information in accordance with our data retention policies.

## 10. Children's Privacy

The Service is not intended for children under the age of 13. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe that your child under 13 has provided us with personal information, please contact us immediately. If we become aware that we have collected personal information from a child under 13 without parental consent, we will take steps to delete that information.

If you are between the ages of 13 and 18, you represent that you have obtained parental or guardian consent to use the Service and that your parent or guardian has reviewed and agreed to our Terms of Service and this Privacy Policy.

## 11. Third-Party Links and Services

The Service may contain links to third-party websites, services, or applications that are not owned or controlled by UltiMafia. This Privacy Policy does not apply to such third-party services. We encourage you to review the privacy policies of any third-party services you access.

We are not responsible for the privacy practices or content of third-party services, including authentication providers (such as Discord or Google) that you may use to access the Service.

## 12. Changes to This Privacy Policy

We may update this Privacy Policy from time to time to reflect changes in our practices, technology, legal requirements, or other factors. We will notify you of any material changes by:

- Posting the updated Privacy Policy on this page with a new "Last Updated" date;
- Sending you an email notification;
- Displaying a prominent notice on the Service.

Your continued use of the Service after the effective date of any changes constitutes your acceptance of the updated Privacy Policy. We encourage you to review this Privacy Policy periodically.

## 13. Data Protection Officer (EU/UK Users)

If you are located in the European Union or United Kingdom and have questions or concerns about our data processing practices, you may contact our Data Protection Officer using the contact information provided in Section 14.

## 14. Contact Us

**By email:** [ultimafia.official@gmail.com](mailto:ultimafia.official@gmail.com)

**Through the Service:** Use the contact methods available on the Service

For EU/UK users exercising their GDPR/UK GDPR rights, please include "GDPR Request" or "UK GDPR Request" in your subject line to help us process your request more efficiently.

For California residents exercising their CCPA rights, please include "CCPA Request" in your subject line.

## 15. Your Consent

By using the Service, you consent to our Privacy Policy and agree to its terms. If you do not agree with this Privacy Policy, please do not use the Service.

"""#

    static let termsOfService = #"""
# Terms of Service

Last Updated: February 6, 2026

Welcome to UltiMafia. These Terms of Service ("Terms") govern your access to and use of the UltiMafia website, services, and applications (collectively, the "Service") operated by UltiMafia ("we," "us," or "our"). By accessing or using our Service, you agree to be bound by these Terms. If you disagree with any part of these Terms, you may not access or use the Service.

## 1. Acceptance of Terms

By creating an account, accessing, or using the Service, you acknowledge that you have read, understood, and agree to be bound by these Terms and our Privacy Policy, which is incorporated herein by reference. These Terms constitute a legally binding agreement between you and UltiMafia.

You must be at least 13 years of age to use the Service. If you are under 18 years of age, you represent that you have obtained parental or guardian consent to use the Service and that your parent or guardian agrees to these Terms on your behalf.

## 2. User Accounts and Registration

To access certain features of the Service, you must create an account. You agree to:

- Provide accurate, current, and complete information during registration;
- Maintain and promptly update your account information to keep it accurate, current, and complete;
- Maintain the security of your account credentials and accept responsibility for all activities that occur under your account;
- Notify us immediately of any unauthorized use of your account or any other breach of security;
- Not share your account credentials with any third party;
- Not use automated means to create accounts.

We reserve the right to suspend or terminate your account if you violate these Terms or engage in any fraudulent, abusive, or illegal activity.

## 3. User-Generated Content and Intellectual Property Rights

**Ownership of User Content:** You retain all ownership rights to any content you upload, post, transmit, or otherwise make available through the Service, including but not limited to avatars, custom emotes, profile banners, profile backgrounds, biographical information, and any other materials (collectively, "User Content").

**Warranty of Rights:** By uploading, posting, or transmitting User Content, you represent and warrant that:

- You own the User Content or possess all necessary rights, licenses, consents, and permissions to use and authorize us to use the User Content as contemplated by these Terms;
- The User Content does not and will not infringe, violate, or misappropriate any third-party rights, including intellectual property rights, privacy rights, or publicity rights;
- You have obtained all necessary consents and releases from any individuals depicted in your User Content;
- The User Content complies with all applicable laws and regulations.

**Removal of User Content:** We reserve the right, but are not obligated, to review, monitor, edit, or remove any User Content at any time, without prior notice, for any reason, including if we determine in our sole discretion that such User Content violates these Terms, is illegal, or is otherwise objectionable.

**No Compensation:** You acknowledge that you will not receive any compensation for the hosting of your User Content by UltiMafia or other users of the Service.

## 4. Acceptable Use Policy

You agree not to use the Service to:

- Violate any applicable local, state, national, or international law or regulation;
- Infringe upon or violate our intellectual property rights or the intellectual property rights of others;
- Harass, abuse, insult, harm, defame, slander, disparage, intimidate, or discriminate based on gender, sexual orientation, religion, ethnicity, race, age, national origin, or disability;
- Submit false or misleading information, including false reports or appeals;
- Upload or transmit viruses, malware, or any other malicious code;
- Collect or track the personal information of others without their consent;
- Spam, phish, pharm, pretext, spider, crawl, or scrape the Service;
- Interfere with or disrupt the Service or servers or networks connected to the Service;
- Attempt to gain unauthorized access to the Service, other accounts, computer systems, or networks connected to the Service;
- Use the Service for any commercial purpose without our express written consent;
- Impersonate any person or entity or misrepresent your affiliation with any person or entity.

Violation of this Acceptable Use Policy may result in immediate termination of your account and potential legal action.

## 5. Rules of Conduct and Moderation

The Service includes community rules and standards of conduct that all users must follow. These rules are detailed in our [Rules of Conduct](https://ultimafia.com/policy/rules) and are incorporated into these Terms by reference. You agree to comply with all applicable rules and understand that violations may result in warnings, temporary suspensions, permanent bans, or other disciplinary actions as determined by our moderation team. The moderation team has sole discretion in enforcing the rules.

We reserve the right to investigate violations of these Terms or our Rules of Conduct and to take appropriate legal action, including but not limited to reporting violations to law enforcement authorities.

## 6. Reporting and Appeals

Users may report violations of our Rules of Conduct through the Service's reporting system. Reports are reviewed by our moderation team, and appropriate action will be taken in accordance with our policies.

If you receive a warning, suspension, or ban, you may appeal the decision through the Service's appeals system. Appeals are reviewed by our moderation team, and decisions are final. We reserve the right to modify or reverse disciplinary actions at our sole discretion.

## 7. Service Availability and Modifications

We reserve the right to modify, suspend, or discontinue the Service, or any part thereof, at any time, with or without notice. We do not guarantee that the Service will be available at all times or that it will be free from errors, defects, or interruptions.

We may update, change, or modify features of the Service at any time. We are not obligated to provide support or maintenance for the Service, though we may do so at our discretion.

## 8. Third-Party Services and Links

The Service may contain links to third-party websites, services, or resources that are not owned or controlled by UltiMafia. We have no control over and assume no responsibility for the content, privacy policies, or practices of any third-party services.

You acknowledge and agree that UltiMafia shall not be responsible or liable, directly or indirectly, for any damage or loss caused or alleged to be caused by or in connection with the use of or reliance on any such content, goods, or services available on or through any such third-party services.

The Service may integrate with third-party authentication providers (such as Discord or Google). Your use of such third-party services is subject to their respective terms of service and privacy policies.

## 9. Disclaimer of Warranties

THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, OR COURSE OF PERFORMANCE.

UltiMafia does not warrant that the Service will be uninterrupted, secure, or error-free, that defects will be corrected, or that the Service or the server that makes it available are free of viruses or other harmful components.

Some jurisdictions do not allow the exclusion of certain warranties, so some of the above exclusions may not apply to you.

## 10. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL ULTIMAFIA, ITS AFFILIATES, AGENTS, DIRECTORS, EMPLOYEES, SUPPLIERS, OR LICENSORS BE LIABLE FOR ANY INDIRECT, PUNITIVE, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR EXEMPLARY DAMAGES, INCLUDING WITHOUT LIMITATION DAMAGES FOR LOSS OF PROFITS, GOODWILL, USE, DATA, OR OTHER INTANGIBLE LOSSES, ARISING OUT OF OR RELATING TO THE USE OF, OR INABILITY TO USE, THE SERVICE.

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, ULTIMAFIA ASSUMES NO LIABILITY OR RESPONSIBILITY FOR ANY (I) ERRORS, MISTAKES, OR INACCURACIES OF CONTENT; (II) PERSONAL INJURY OR PROPERTY DAMAGE, OF ANY NATURE WHATSOEVER, RESULTING FROM YOUR ACCESS TO OR USE OF OUR SERVICE; (III) ANY UNAUTHORIZED ACCESS TO OR USE OF OUR SECURE SERVERS AND/OR ANY AND ALL PERSONAL INFORMATION STORED THEREIN; (IV) ANY INTERRUPTION OR CESSATION OF TRANSMISSION TO OR FROM THE SERVICE; (V) ANY BUGS, VIRUSES, TROJAN HORSES, OR THE LIKE, WHICH MAY BE TRANSMITTED TO OR THROUGH THE SERVICE BY ANY THIRD PARTY; AND/OR (VI) ANY ERRORS OR OMISSIONS IN ANY CONTENT OR FOR ANY LOSS OR DAMAGE OF ANY KIND INCURRED AS A RESULT OF YOUR USE OF ANY CONTENT POSTED, EMAILED, TRANSMITTED, OR OTHERWISE MADE AVAILABLE VIA THE SERVICE.

IN NO EVENT SHALL ULTIMAFIA'S TOTAL LIABILITY TO YOU FOR ALL DAMAGES EXCEED THE AMOUNT YOU PAID TO ULTIMAFIA IN THE TWELVE (12) MONTHS PRIOR TO THE ACTION GIVING RISE TO LIABILITY, OR ONE HUNDRED DOLLARS ($100), WHICHEVER IS GREATER.

Some jurisdictions do not allow the exclusion or limitation of incidental or consequential damages, so the above limitations or exclusions may not apply to you.

## 11. Indemnification

You agree to defend, indemnify, and hold harmless UltiMafia and its affiliates, licensors, and service providers, and their respective officers, directors, employees, contractors, agents, licensors, suppliers, successors, and assigns from and against any claims, liabilities, damages, judgments, awards, losses, costs, expenses, or fees (including reasonable attorneys' fees) arising out of or relating to your violation of these Terms or your use of the Service, including but not limited to your User Content, any use of the Service's content, services, and products other than as expressly authorized in these Terms, or your use of any information obtained from the Service.

## 12. Termination

We may terminate or suspend your account and access to the Service immediately, without prior notice or liability, for any reason, including if you breach these Terms.

Upon termination, your right to use the Service will immediately cease. If you wish to terminate your account, you may do so by contacting us or using the account deletion feature, if available.

All provisions of these Terms which by their nature should survive termination shall survive termination, including, without limitation, ownership provisions, warranty disclaimers, indemnity, and limitations of liability.

## 13. Changes to Terms

We reserve the right, at our sole discretion, to modify or replace these Terms at any time. If a revision is material, we will provide at least 30 days' notice prior to any new terms taking effect. What constitutes a material change will be determined at our sole discretion.

By continuing to access or use our Service after any revisions become effective, you agree to be bound by the revised terms. If you do not agree to the new terms, you are no longer authorized to use the Service.

## 14. Governing Law and Dispute Resolution

**For Users in the European Union and United Kingdom:** These Terms shall be governed by and construed in accordance with the laws of the jurisdiction in which UltiMafia operates, without regard to its conflict of law provisions. Any disputes arising out of or relating to these Terms or the Service shall be subject to the exclusive jurisdiction of the courts of that jurisdiction. However, if you are a consumer resident in the EU or UK, you may also bring proceedings in your country of residence.

**For Users in the United States:** These Terms shall be governed by and construed in accordance with the laws of the State of [Your State], United States, without regard to its conflict of law provisions. Any disputes arising out of or relating to these Terms or the Service shall be resolved through binding arbitration in accordance with the rules of the American Arbitration Association, except that you may assert claims in small claims court if your claims qualify.

You and UltiMafia agree that any dispute resolution proceedings will be conducted only on an individual basis and not in a class, consolidated, or representative action.

## 15. Severability

If any provision of these Terms is held to be invalid or unenforceable by a court, the remaining provisions of these Terms will remain in effect. The invalid or unenforceable provision will be replaced with a valid provision that comes closest to the intent of the invalid provision.

## 16. Entire Agreement

These Terms, together with our Privacy Policy and Rules of Conduct, constitute the entire agreement between you and UltiMafia regarding the Service and supersede all prior and contemporaneous written or oral agreements between you and UltiMafia.

## 17. Contact Information

If you have any questions about these Terms, please contact us through the Service's contact methods or by emailing us at the contact information provided in our Privacy Policy.

## 18. Acknowledgment

BY USING THE SERVICE, YOU ACKNOWLEDGE THAT YOU HAVE READ THESE TERMS OF SERVICE AND AGREE TO BE BOUND BY THEM.

"""#
}

/// Native legal page (pushed inside Advanced Settings; standard back button).
struct UMLegalView: View {
    let title: String
    let markdown: String

    var body: some View {
        ScrollView {
            UMMarkdownView(text: markdown)
                .padding(16)
                .textSelection(.enabled)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .navigationTitle(title)
        .umInlineTitle()
    }
}
