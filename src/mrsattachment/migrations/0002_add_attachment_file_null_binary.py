# Generated by Django 2.1.9 on 2019-07-02 13:09

import django.core.files.storage
from django.db import migrations, models
from mrs.settings import ATTACHMENT_ROOT
import mrsattachment.models

class Migration(migrations.Migration):

    dependencies = [
        ('mrsattachment', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='mrsattachment',
            name='attachment_file',
            field=models.FileField(default='', null=True, storage=django.core.files.storage.FileSystemStorage(location=ATTACHMENT_ROOT), upload_to=mrsattachment.models.MRSAttachment.attachment_file_path, verbose_name='Attachement'),
        ),
        migrations.AlterField(
            model_name='mrsattachment',
            name='binary',
            field=models.BinaryField(null=True),
        ),
    ]
