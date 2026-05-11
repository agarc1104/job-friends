import 'package:flutter/material.dart';

import '../../data/jobfriends_repository.dart';
import '../../models/application_record.dart';
import '../../models/user_profile.dart';

class InterviewPrepScreen extends StatefulWidget {
  const InterviewPrepScreen({required this.currentUser, super.key});

  final UserProfile? currentUser;

  @override
  State<InterviewPrepScreen> createState() => _InterviewPrepScreenState();
}

class _InterviewPrepScreenState extends State<InterviewPrepScreen> {
  final _repository = const JobFriendsRepository();
  final _messageController = TextEditingController();
  final List<Map<String, String>> _history = [];
  bool _isSending = false;
  List<ApplicationRecord> _applications = const [];
  ApplicationRecord? _selected;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  @override
  void didUpdateWidget(covariant InterviewPrepScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser?.email != widget.currentUser?.email) {
      _history.clear();
      _selected = null;
      _loadApplications();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    final user = widget.currentUser;
    if (user == null) {
      setState(() {
        _applications = const [];
        _selected = null;
      });
      return;
    }

    try {
      final apps = await _repository.fetchApplications(user.email);
      if (!mounted) {
        return;
      }
      setState(() {
        _applications = apps;
        _selected = apps.isEmpty ? null : apps.first;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _applications = const [];
        _selected = null;
      });
    }
  }

  Future<void> _sendMessage() async {
    final user = widget.currentUser;
    final selected = _selected;
    final message = _messageController.text.trim();
    if (user == null || selected == null || message.isEmpty) {
      return;
    }

    setState(() {
      _isSending = true;
      _history.add({'role': 'user', 'content': message});
      _messageController.clear();
    });

    try {
      final reply = await _repository.requestInterviewReply(
        jobTitle: selected.vacancy,
        jobDescription: selected.description,
        applicationLink: selected.applicationLink,
        history: _history,
        userMessage: message,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _history.add({'role': 'assistant', 'content': reply});
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interview Prep',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ApplicationRecord>(
                    key: ValueKey(_selected?.id ?? 'empty'),
                    initialValue: _selected,
                    decoration: const InputDecoration(
                      labelText: 'Vacante aplicada',
                      border: OutlineInputBorder(),
                    ),
                    items: _applications
                        .map(
                          (item) => DropdownMenuItem<ApplicationRecord>(
                            value: item,
                            child: Text(item.vacancy),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selected = value;
                        _history.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final item = _history[index];
              final isUser = item['role'] == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFFD6F2EA) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD8E4E0)),
                  ),
                  child: Text(item['content'] ?? ''),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Pregunta sobre la entrevista...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _isSending ? null : _sendMessage,
                child: Text(_isSending ? '...' : 'Enviar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}