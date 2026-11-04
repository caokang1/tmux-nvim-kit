package com.example.demo.service;

public abstract class AbstractService {
    protected String serviceName() {
        return getClass().getSimpleName();
    }

    public abstract void audit(String action);
}
