# wsgi.py - Gunicorn will use this
from fractal_app import app

if __name__ == "__main__":
    app.run()
