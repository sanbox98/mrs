# Generated by Django 2.1.6 on 2019-04-08 10:43
import re

from django.db import migrations, models
import django.db.models.deletion


def provision_emailtemplate(apps, schema_editor):
    EmailTemplate = apps.get_model('mrsemail', 'EmailTemplate')
    MRSRequestLogEntry = apps.get_model('mrsrequest', 'MRSRequestLogEntry')

    templates = {
        et.subject.replace(
            '{{ display_id }}',
            '\d+',
        ).replace(
            '******** A renseigner ********',
            '.*',
        ): et for et in EmailTemplate.objects.all()
    }

    for logentry in MRSRequestLogEntry.objects.exclude(data=None):
        title = logentry.data.get('subject', None)

        if title is None:
            continue

        for subject, template in templates.items():
            if re.match(subject, title):
                logentry.emailtemplate = template
                logentry.save()
                break


class Migration(migrations.Migration):

    dependencies = [
        ('mrsemail', '0005_counter'),
        ('mrsrequest', '0038_add_mrsrequest_pel'),
    ]

    operations = [
        migrations.AddField(
            model_name='mrsrequestlogentry',
            name='emailtemplate',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, to='mrsemail.EmailTemplate'),
        ),
        migrations.RunPython(provision_emailtemplate),
    ]
