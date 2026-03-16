import tkinter as tk
from tkinter import ttk


def setup_styles():
    style = ttk.Style()
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass
    style.configure("TFrame", background="#E8F0FE")
    style.configure("TLabel", background="#E8F0FE", foreground="#2C3E50", font=("Arial", 10))
    style.configure("Header.TLabel", font=("Arial", 14, "bold"), foreground="#4285F4", background="#E8F0FE")
    style.configure("TButton", background="#4285F4", foreground="white", font=("Arial", 10, "bold"))
    style.map("TButton", background=[("active", "#3367D6"), ("disabled", "#A0A0A0")])
    style.configure("TEntry", padding=5, relief="flat", fieldbackground="white", foreground="#2C3E50")
    style.configure("Treeview", background="white", fieldbackground="white", foreground="#2C3E50")
    style.configure("Treeview.Heading", background="#4285F4", foreground="white", font=("Arial", 10, "bold"))
