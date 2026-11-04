package com.example.demo.service.impl;

import com.example.demo.entity.User;
import com.example.demo.mapper.UserMapper;
import com.example.demo.service.AbstractService;
import com.example.demo.service.UserService;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class UserServiceImpl extends AbstractService implements UserService {

    @Autowired
    private UserMapper userMapper;

    @Value("${demo.name}")
    private String appName;

    private int counter;

    @Override
    public User getUser(Long id) {
        counter++;
        audit("get");
        return userMapper.selectById(id);
    }

    @Override
    public List<User> listUsers() {
        List<User> result = new ArrayList<>(userMapper.selectAll());
        audit("list " + counter);
        return result;
    }

    @Override
    public void saveUser(User user) {
        userMapper.insertUser(user);
    }

    @Override
    public void audit(String action) {
        System.out.println(appName + ": " + action);
    }

    @Override
    protected String serviceName() {
        return "user";
    }
}
