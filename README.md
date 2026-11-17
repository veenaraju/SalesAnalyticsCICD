# Sales Analytics – Local CI/CD Demo

This starter project demonstrates a build-artifact deployment flow using GitHub Actions
and a Windows self-hosted runner. DEV and QA are logical environments on one Windows
machine; they use separate virtual environments, `.env` files, ports, and MySQL databases.

## 1. Prerequisites

- Windows 10/11
- Python 3.11 available as `py -3.11`
- Git
- MySQL Server running locally
- A GitHub repository
- A Windows self-hosted GitHub Actions runner with labels:
  `self-hosted`, `Windows`, `X64`, `sales-local`
- Network access during the CI build so `pip download` can populate the wheelhouse

All workflow jobs use the same runner. The artifact is stored on that runner's local disk,
so a single runner is the simplest configuration for this demonstration.

## 2. Create the MySQL databases

Run `sql/create_databases.sql` using a MySQL account allowed to create databases.
Then run `sql/create_tables.sql` once in each database (`sales_dev` and `sales_qa`).
The SQL seed script is intended to be executed separately while connected to each database.

Example using the MySQL command-line client:

```powershell
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS sales_dev; CREATE DATABASE IF NOT EXISTS sales_qa;"
mysql -u root -p sales_dev < sql/create_tables.sql
mysql -u root -p sales_qa < sql/create_tables.sql
```

## 3. Prepare local DEV and QA folders

```powershell
$Root = "C:\users\veens\Deployment\SalesAnalyticsCICD"
New-Item -ItemType Directory -Force "$Root\DEV", "$Root\QA", "$Root\artifacts"
Copy-Item .env.example "$Root\DEV\.env"
Copy-Item .env.example "$Root\QA\.env"
notepad "$Root\DEV\.env"
notepad "$Root\QA\.env"
```

Set the database URL in DEV to `sales_dev` and in QA to `sales_qa`.
Replace `CHANGE_ME` with the MySQL password. If it contains URL-reserved characters,
URL-encode those characters.

Example:
`DATABASE_URL=mysql+pymysql://sales_user:your_password@localhost:3306/sales_dev`

The QA file should end with `/sales_qa`.

**Important:** each environment folder contains a file literally named `.env`.
Do not put `.env` in the Git repository or inside the deployment ZIP.

## 4. Test the app locally before CI/CD

From the repository root:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements-dev.txt
python -m pip install -e .
ruff check .
python -m pytest tests/ -v
streamlit run app.py
```

For this first local run, create a temporary `.env` in the repository root with a
`DATABASE_URL` pointing to `sales_dev`. Remove it before committing; `.gitignore`
excludes it.

## 5. Configure GitHub

1. Push this project to the GitHub repository.
2. Register the Windows self-hosted runner and add the custom label `sales-local`.
3. In repository Settings → Environments, create `dev` and `qa`.
4. Configure required reviewers on `qa` if supported by the repository/plan.
5. Protect `main` and require the CI checks before merge.
6. Ensure the runner service account can access the deployment root, MySQL, and local ports.

## 6. Start with a baseline deployment

Merge the initial working project to `main`. The workflow runs checks, builds a wheel,
creates an offline ZIP artifact on the runner, deploys it to DEV, then waits at the QA
environment approval gate before deploying the same ZIP to QA.

- DEV: http://localhost:8501
- QA: http://localhost:8502

## 7. Artifact behaviour

The deployable ZIP contains `app.py`, `requirements-runtime.txt`, `build-info.txt`, and
`wheels/` (the business package wheel plus runtime dependency wheels). It does not contain
the source tree, tests, Git metadata, development dependencies, or environment secrets.

A push to a feature branch or a pull request runs quality checks. After the PR is merged,
the push to `main` builds the merged-main artifact. That artifact is the one deployed to
DEV and then QA. QA does not rebuild the application.

## 8. Important demo limitation

This is a local demonstration, not a highly available production deployment. DEV and QA
are separate application folders and database schemas on one Windows host. The deployment
script stops and restarts Streamlit; a production implementation should add health checks,
versioned release folders, rollback, service management, and stronger secret handling.
