import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/jobfriends_repository.dart';
import '../ads/rewarded_interstitial_ads_service.dart';
import '../../l10n/localized_text.dart';
import '../../models/application_record.dart';
import '../../models/interview_message.dart';
import '../../models/interview_practice_mode.dart';
import '../../models/interview_session.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';

class InterviewChatScreen extends StatefulWidget {
  const InterviewChatScreen({
    required this.currentUser,
    this.application,
    this.initialSession,
    this.initialMode,
    this.startNew = false,
    super.key,
  });

  final UserProfile currentUser;
  final ApplicationRecord? application;
  final InterviewSession? initialSession;
  final InterviewPracticeMode? initialMode;
  final bool startNew;

  @override
  State<InterviewChatScreen> createState() => _InterviewChatScreenState();
}

class _InterviewChatScreenState extends State<InterviewChatScreen> {
  final _repository = const JobFriendsRepository();
  final _rewardedInterstitialAds = RewardedInterstitialAdsService.instance;
  final _messageController = TextEditingController();
  final List<Map<String, dynamic>> _history = [];

  bool _isLoading = true;
  bool _awaitingAiFirstReply = false;
  bool _isSending = false;
  List<InterviewMessage> _messages = const [];
  InterviewSession? _activeSession;
  String _sessionSummary = '';

  @override
  void initState() {
    super.initState();
    unawaited(_rewardedInterstitialAds.preload());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    if (widget.startNew) {
      await _startNewChat();
      return;
    }

    final session = widget.initialSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final messages = await _repository.fetchInterviewMessages(sessionId: session.id);
    if (!mounted) {
      return;
    }

    setState(() {
      _activeSession = session;
      _sessionSummary = session.lastSummary;
      _messages = messages;
      _isLoading = false;
    });
    _rebuildHistory();
  }

  void _rebuildHistory() {
    _history.clear();
    for (final msg in _messages) {
      _history.add(msg.toFunctionHistoryMap());
    }
  }

  Future<void> _startNewChat() async {
    final application = widget.application;
    final mode = widget.initialMode;
    if (application == null || mode == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final eligibleApplication = await _ensureEligibleApplicationForStorage(application.id);
    if (eligibleApplication == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _awaitingAiFirstReply = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    final languageCode = languageCodeFromLocale(Localizations.localeOf(context));

    if (mounted) {
      setState(() {
        _isLoading = true;
        _awaitingAiFirstReply = true;
      });
    }

    try {
      final starterPrompts = mode.starterPromptsFor(languageCode);
      final starterPrompt = starterPrompts.isNotEmpty
          ? starterPrompts.first
          : trByCode(
              languageCode,
              'interview.startFallback',
              fallback: 'Iniciemos la entrevista.',
            );

      final reply = await _repository.requestInterviewReply(
        jobTitle: eligibleApplication.vacancy,
        jobDescription: eligibleApplication.description,
        applicationLink: eligibleApplication.applicationLink,
        history: const [],
        userMessage: '',
        bootstrapPrompt: starterPrompt,
        mode: mode,
      );

      final eligibleAfterReply = await _ensureEligibleApplicationForStorage(eligibleApplication.id);
      if (eligibleAfterReply == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _awaitingAiFirstReply = false;
        });
        return;
      }

      await _rewardedInterstitialAds.maybeShow(
        placement: 'interview_before_session',
        userEmail: widget.currentUser.email,
      );

      await _repository.archiveActiveInterviewSession(
        applicantEmail: widget.currentUser.email,
        applicationId: eligibleAfterReply.id,
        mode: mode,
      );

      final session = await _repository.createInterviewSession(
        applicantEmail: widget.currentUser.email,
        applicationId: eligibleAfterReply.id,
        mode: mode,
      );

      if (session == null) {
        throw const JobFriendsRepositoryException('No se pudo iniciar una nueva sesion.');
      }

      final assistantMessage = InterviewMessage(
        role: 'assistant',
        content: reply.reply,
        createdAt: DateTime.now(),
        coachFeedback: reply.coachFeedback,
        improvedAnswer: reply.improvedAnswer,
        nextQuestion: reply.nextQuestion,
        score: reply.score,
        tags: reply.tags,
        sessionSummary: reply.sessionSummary,
      );

      await _repository.saveInterviewMessage(
        message: assistantMessage,
        sessionId: session.id,
        applicantEmail: widget.currentUser.email,
        applicationId: eligibleAfterReply.id,
        mode: mode,
      );

      if (reply.sessionSummary.isNotEmpty) {
        await _repository.updateInterviewSessionSummary(
          sessionId: session.id,
          summary: reply.sessionSummary,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeSession = session;
        _sessionSummary = reply.sessionSummary;
        _messages = [assistantMessage];
        _history
          ..clear()
          ..add({'role': 'assistant', 'content': assistantMessage.content});
        _isLoading = false;
        _awaitingAiFirstReply = false;
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _awaitingAiFirstReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _awaitingAiFirstReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo iniciar la entrevista.')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final session = _activeSession;
    final application = widget.application;
    final message = _messageController.text.trim();

    if (session == null || application == null || message.isEmpty) {
      return;
    }

    final eligibleApplication = await _ensureEligibleApplicationForStorage(application.id);
    if (eligibleApplication == null) {
      return;
    }

    setState(() {
      _isSending = true;
      _history.add({'role': 'user', 'content': message});
      _messages = [
        ..._messages,
        InterviewMessage(
          role: 'user',
          content: message,
          createdAt: DateTime.now(),
        ),
      ];
      _messageController.clear();
    });

    try {
      final reply = await _repository.requestInterviewReply(
        jobTitle: eligibleApplication.vacancy,
        jobDescription: eligibleApplication.description,
        applicationLink: eligibleApplication.applicationLink,
        history: _history,
        userMessage: message,
        mode: session.mode,
        sessionSummary: _sessionSummary,
      );

      final eligibleAfterReply = await _ensureEligibleApplicationForStorage(eligibleApplication.id);
      if (eligibleAfterReply == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      final assistantMessage = InterviewMessage(
        role: 'assistant',
        content: reply.reply,
        createdAt: DateTime.now(),
        coachFeedback: reply.coachFeedback,
        improvedAnswer: reply.improvedAnswer,
        nextQuestion: reply.nextQuestion,
        score: reply.score,
        tags: reply.tags,
        sessionSummary: reply.sessionSummary,
      );

      setState(() {
        _history.add({'role': 'assistant', 'content': reply.reply});
        _messages = [..._messages, assistantMessage];
        if (reply.sessionSummary.isNotEmpty) {
          _sessionSummary = reply.sessionSummary;
        }
      });

      await _repository.saveInterviewMessage(
        sessionId: session.id,
        applicantEmail: widget.currentUser.email,
        applicationId: eligibleAfterReply.id,
        mode: session.mode,
        message: InterviewMessage(
          role: 'user',
          content: message,
          createdAt: DateTime.now(),
        ),
      );
      await _repository.saveInterviewMessage(
        sessionId: session.id,
        applicantEmail: widget.currentUser.email,
        applicationId: eligibleAfterReply.id,
        mode: session.mode,
        message: assistantMessage,
      );

      if (reply.sessionSummary.isNotEmpty) {
        await _repository.updateInterviewSessionSummary(
          sessionId: session.id,
          summary: reply.sessionSummary,
        );
      }
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar respuesta de entrevista.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<ApplicationRecord?> _ensureEligibleApplicationForStorage(String applicationId) async {
    final application = await _repository.fetchApplicationById(
      applicantEmail: widget.currentUser.email,
      applicationId: applicationId,
    );

    if (application == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se guardan chats de vacantes eliminadas.')),
      );
      return null;
    }

    if (application.isOlderThanThreeMonths) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se guardan chats de vacantes con mas de 3 meses desde la postulacion.')),
      );
      return null;
    }

    return application;
  }

  String _phaseLabel(int userTurns) {
    if (userTurns < 2) return tr(context, 'interview.phase.start');
    if (userTurns < 4) return tr(context, 'interview.phase.warmup');
    if (userTurns < 7) return tr(context, 'interview.phase.technical');
    if (userTurns < 10) return tr(context, 'interview.phase.advanced');
    return tr(context, 'interview.phase.closing');
  }

  void _showSessionReport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'interview.sessionReport')),
        content: SingleChildScrollView(
          child: Text(
            _sessionSummary.isEmpty ? tr(context, 'interview.noSessionData') : _sessionSummary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'common.close')),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(content, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final session = _activeSession;
    final userTurns = _messages.where((item) => item.isUser).length;
    final totalSteps = 12;
    final progress = (userTurns / totalSteps).clamp(0.0, 1.0);
    final composerEnabled =
        session != null &&
        application != null &&
        session.status == 'active' &&
        !_isLoading &&
        !_awaitingAiFirstReply &&
        !_isSending;

    return Scaffold(
      appBar: AppBar(
        title: Text(application?.vacancy ?? 'Vacante eliminada'),
        actions: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: SizedBox(
                width: 108,
                child: FilledButton.tonalIcon(
                  onPressed: _showSessionReport,
                  icon: const Icon(Icons.assessment_outlined, size: 18),
                  label: Text(tr(context, 'common.report')),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      if (session != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.mode.labelFor(
                                    languageCodeFromLocale(Localizations.localeOf(context)),
                                  ),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      tr(context, 'interview.phase', args: {'phase': _phaseLabel(userTurns)}),
                                      style: Theme.of(context).textTheme.labelMedium,
                                    ),
                                    Text(
                                      '$userTurns/$totalSteps',
                                      style: Theme.of(context).textTheme.labelMedium,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(value: progress),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_messages.isEmpty && application == null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              'Esta vacante fue eliminada. Puedes revisar el historial, pero para continuar debes iniciar un nuevo chat.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final item = _messages[index];
                            final isUser = item.isUser;
                            final maxBubbleWidth = MediaQuery.of(context).size.width * 0.8;
                            return Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                                decoration: BoxDecoration(
                                  color: isUser ? AppColors.softGreen : AppColors.surface,
                                  borderRadius: BorderRadius.circular(AppRadii.sm),
                                  border: Border.all(
                                    color: isUser ? AppColors.softGreenBorder : AppColors.softSurfaceBorder,
                                  ),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isUser ? tr(context, 'interview.you') : tr(context, 'interview.ai'),
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: isUser ? AppColors.primaryActive : AppColors.secondaryText,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(item.content),
                                    if (!isUser && item.coachFeedback.trim().isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      _buildInfoBlock(
                                        context,
                                        title: tr(context, 'interview.feedback'),
                                        content: item.coachFeedback,
                                      ),
                                    ],
                                    if (!isUser && item.improvedAnswer.trim().isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      _buildInfoBlock(
                                        context,
                                        title: tr(context, 'interview.improvedVersion'),
                                        content: item.improvedAnswer,
                                      ),
                                    ],
                                    if (!isUser && item.nextQuestion.trim().isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      _buildInfoBlock(
                                        context,
                                        title: tr(context, 'interview.nextChallenge'),
                                        content: item.nextQuestion,
                                      ),
                                    ],
                                    if (!isUser && item.score != null) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        tr(context, 'interview.score', args: {
                                          'score': item.score!.toStringAsFixed(1),
                                        }),
                                        style: Theme.of(context).textTheme.labelMedium,
                                      ),
                                    ],
                                    if (!isUser && item.tags.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: item.tags
                                            .map(
                                              (tag) => Chip(
                                                label: Text(tag),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: AppColors.softSurfaceBorder),
                          boxShadow: AppShadows.card,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tr(context, 'interview.yourAnswer'),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _messageController,
                                    maxLines: null,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) {
                                      if (!composerEnabled) return;
                                      _sendMessage();
                                    },
                                    enabled: composerEnabled,
                                    decoration: InputDecoration(
                                      hintText: composerEnabled
                                          ? tr(context, 'interview.answerHint')
                                          : 'Sesion en solo lectura. Inicia un nuevo chat.',
                                      border: InputBorder.none,
                                      filled: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            SizedBox(
                              width: 56,
                              height: 56,
                              child: FilledButton(
                                onPressed: composerEnabled ? _sendMessage : null,
                                child: _isSending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
