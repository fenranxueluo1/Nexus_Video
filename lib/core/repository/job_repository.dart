import 'dart:io';

import '../domain/jobs.dart';
import '../util/storage_paths.dart';
import '../util/durable_json.dart';

class JobRepository {
  JobRepository({File? jobsFile, File? recordsFile})
    : _jobsFile = jobsFile ?? StoragePaths.jobsFile,
      _recordsFile = recordsFile ?? StoragePaths.recordsFile;

  final File _jobsFile;
  final File _recordsFile;

  Future<List<TransferJob>> loadJobs() async {
    final json = await DurableJson.readMap(_jobsFile);
    if (json == null) {
      return [];
    }
    final jobs = <TransferJob>[];
    for (final entry in (json['jobs'] as List? ?? const [])) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      try {
        jobs.add(TransferJob.fromJson(entry));
      } on Object {
        continue;
      }
    }
    return jobs;
  }

  Future<void> saveJobs(List<TransferJob> jobs) async {
    await DurableJson.writeJson(_jobsFile, {
      'schemaVersion': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'jobs': jobs.map((job) => job.toJson()).toList(),
    });
  }

  Future<List<CompletionRecord>> loadRecords() async {
    final json = await DurableJson.readMap(_recordsFile);
    if (json == null) {
      return [];
    }
    final records = <CompletionRecord>[];
    for (final entry in (json['records'] as List? ?? const [])) {
      if (entry is Map<String, dynamic>) {
        try {
          records.add(CompletionRecord.fromJson(entry));
        } on Object {
          continue;
        }
      }
    }
    records.sort(
      (left, right) => right.completedAt.compareTo(left.completedAt),
    );
    return records;
  }

  Future<void> saveRecords(List<CompletionRecord> records) async {
    await DurableJson.writeJson(_recordsFile, {
      'schemaVersion': 1,
      'records': records.map((record) => record.toJson()).toList(),
    });
  }

  Future<void> appendJournal(String jobId, JournalEntry entry) async {
    await DurableJson.appendLine(
      StoragePaths.journalFileFor(jobId),
      entry.toJson(),
    );
  }

  Future<List<JournalEntry>> readJournal(
    String jobId, {
    int limit = 200,
  }) async {
    final rows = await DurableJson.readLines(
      StoragePaths.journalFileFor(jobId),
      limit: limit,
    );
    return rows.map(JournalEntry.fromJson).toList();
  }

  Future<void> deleteJournal(String jobId) async {
    final file = StoragePaths.journalFileFor(jobId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
