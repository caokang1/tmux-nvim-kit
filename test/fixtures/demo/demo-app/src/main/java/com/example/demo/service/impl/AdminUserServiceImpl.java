package com.example.demo.service.impl;

import com.example.demo.entity.User;
import com.example.demo.service.UserService;
import java.util.Collections;
import java.util.List;

public class AdminUserServiceImpl implements UserService {
    @Override
    public User getUser(Long id) {
        return null;
    }

    @Override
    public List<User> listUsers() {
        return Collections.emptyList();
    }

    @Override
    public void saveUser(User user) {
    }
}
