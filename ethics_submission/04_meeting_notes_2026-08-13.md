# Ethics Application Meeting Notes

## Decisions Needed From Simon / Principal Investigator

1. Confirm the principal investigator who will submit and sign the application.
2. Confirm recruitment route for approximately 100 adults: personal network only, TU mailing lists, participant pool, social media, or a combination.
3. Confirm compensation or explicitly state that participation is unpaid. Avoid recruiting anyone in a dependency relationship where participation could feel obligatory.
4. Confirm study setting: supervised sessions, remote participation on participants' own Android phones, or both.
5. Confirm the participant-facing duration after a pilot. Current ethical draft uses 25--40 minutes plus possible model-download time; the app currently says about 15 minutes.
6. Confirm the PEASEC/TU server, hosting location, encrypted upload method, access-control list, backups, and responsible data handler.
7. Confirm deletion periods for working/pseudonymized data, anonymized data, and consent records.
8. Confirm the last date or processing milestone at which a participant can request deletion using the study ID.
9. Confirm whether pseudonymized record-level data may be reused. Recommended default: only anonymized aggregate results for the thesis and related publication, with no unapproved reuse.
10. Confirm Dr. Nina Gerber's formal role and whether she should be listed as participating researcher, co-supervisor, principal investigator, or consultant.

## Required App/Data-Flow Fixes Before Data Collection

1. Replace exported original filenames and local URIs with random per-file identifiers. Filenames can themselves contain names, account numbers, course details, or other personal data.
2. Do not download the 2.5 GB Gemma model directly from Hugging Face during the production study unless the third-party IP-address disclosure is documented and approved. Prefer TU-hosted distribution, supervised preinstallation, or another approved route.
3. Explicitly delete every temporary camera file after reading it. The current camera API creates a temporary image file; saying that no image is stored is accurate only after immediate deletion is implemented and tested.
4. Decide whether optional reaction tracking should cover the entire study. The current camera widget exists on the pre-questionnaire page and is disposed when the participant moves to file analysis, so it does not currently measure reactions to the inferences/profile.
5. Generate and display a random study ID. Include it in the export and provide it to the participant for withdrawal requests.
6. Ensure the app offers the complete participant information/privacy statement for download or retention, not only a short consent card.
7. Make every required questionnaire item explicit. The current sliders visually default to a midpoint; decide whether unanswered items must be actively confirmed or may remain missing.
8. Add demographic options: prefer not to say for age; self-description for gender; other for education.
9. Ensure raw selected files, rendered PDF previews, camera frames, and image bytes never appear in the exported JSON or server logs.
10. Verify encrypted transport, certificate validation, failed-upload handling, local export cleanup, and server-side deletion before recruitment.

## Methodological Questions

1. Keep IUIPC-8 and ATI as validated baseline scales. Confirm scoring and planned analysis with Nina.
2. Decide whether the two extra baseline items that duplicate ATI/privacy concern are needed.
3. Confirm whether optional emotion labels have a clear hypothesis or remain explicitly exploratory. They should not be treated as ground truth for participants' emotions.
4. Confirm whether approximately 20 files is mandatory, a target, or a maximum. Define how incomplete sessions are handled.
5. Confirm whether only the first page of a PDF is scientifically sufficient and disclose this consistently.
6. Define the primary outcomes before data collection: likely per-inference unexpectedness/sensitivity/accuracy and changes in local-AI expectations, concern, reassurance, and access willingness.
7. Decide how inaccurate or failed Gemma outputs are treated in analysis and whether participants can flag nonsensical results.
8. Consider whether prompts should avoid deliberately inferring special-category data such as health, religion, political opinions, or sexual orientation, or whether those possible inferences are central and require explicit consent and stronger safeguards.

## Ethics Submission Process

1. Data collection must not begin before a positive vote.
2. Submit one PDF in this order: application form, informed consent/information sheet, questionnaires, other supporting documents.
3. The principal investigator must sign the application.
4. Remove all red `TO CONFIRM` text and internal notes before submission.
5. Make the app, consent text, questionnaire appendix, and described data flow match exactly before recruitment.
