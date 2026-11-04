package com.example.demo.service;

import com.example.demo.entity.User;
import java.util.List;

public interface UserService {
    User getUser(Long id);

    List<User> listUsers();

    void saveUser(User user);
}
