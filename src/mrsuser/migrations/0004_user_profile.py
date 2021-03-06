# Generated by Django 2.0.5 on 2018-07-26 20:57

from django.db import migrations, models


def provision_profile(apps, schema_editor):
    User = apps.get_model('mrsuser', 'User')
    User.objects.filter(
        is_staff=True,
        is_superuser=False
    ).update(profile='upn')
    User.objects.filter(is_superuser=True).update(profile='admin')


class Migration(migrations.Migration):

    dependencies = [
        ('mrsuser', '0003_meta'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='profile',
            field=models.CharField(max_length=50, null=True, verbose_name='profil'),
        ),
        migrations.RunPython(provision_profile),
        migrations.AlterField(
            model_name='user',
            name='profile',
            field=models.CharField(choices=[('admin', 'Admin'), ('upn', 'UPN'), ('stat', 'Stat'), ('support', 'Relation client')], max_length=50, verbose_name='profil'),
        ),
        migrations.RemoveField(
            model_name='user',
            name='is_staff',
        ),
        migrations.RemoveField(
            model_name='user',
            name='is_superuser',
        ),
    ]
