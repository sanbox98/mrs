# Generated by Django 2.0.4 on 2018-04-27 13:57

from django.db import migrations, models


def status_to_logentry(apps, schema_editor):
    MRSRequest = apps.get_model('mrsrequest', 'MRSRequest')
    LogEntry = apps.get_model('admin', 'LogEntry')
    ContentType = apps.get_model('contenttypes', 'ContentType')
    c = ContentType.objects.get_for_model(MRSRequest)

    for m in MRSRequest.objects.all():
        # Update to status that is compatible with LogEntry flags
        if m.status == 0:
            m.status = 1  # NEW
        elif m.status == 1:
            m.status = 999  # REJECT
            if m.reject_template_id:
                message = m.reject_template.subject
            else:
                message = 'Rejetée'
        elif m.status == 2:
            m.status = 1000  # PROGRESS
            message = 'En cours de liquidation'
        elif m.status == 9:
            m.status = 2000  # DONE
            message = 'Validée'
        m.save()

        if m.status == 1:
            continue  # nothing left for new requests

        # Delete all LogEntries and start over from scratch
        # They should only in staging, this is supposed to be noop in
        # production
        LogEntry.objects.filter(
            content_type=c,
            object_id=m.pk,
        ).delete()

        if not m.status_datetime:
            continue  # Old requests without status_datetime

        LogEntry.objects.create(
            user=m.status_user,
            action_time=m.status_datetime,
            content_type=c,
            object_id=m.pk,
            object_repr=m.display_id,
            action_flag=m.status,
            change_message=message,
        )


class Migration(migrations.Migration):

    dependencies = [
        ('mrsrequest', '0003_mrsrequest_reject_template_set_null'),
        ('admin', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(status_to_logentry),
        migrations.AlterField(
            model_name='mrsrequest',
            name='status',
            field=models.IntegerField(choices=[(1, 'Soumise'), (999, 'Rejetée'), (1000, 'En cours de liquidation'), (2000, 'Validée')], default=0, verbose_name='Statut'),
        ),
    ]