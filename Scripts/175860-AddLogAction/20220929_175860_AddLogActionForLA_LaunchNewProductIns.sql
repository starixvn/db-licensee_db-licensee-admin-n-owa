/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20220929@Malcolm
	DB: DBLOG.bodb_CustomerLog
	Task: Add log for LA_LaunchNewProductIns RedmineId #175860
*/
USE [bodb_CustomerLog]
GO

INSERT INTO [dbo].[LogAction]
       ([ActionID]
       ,[SPName]
       ,[ActionNameEN]
       ,[ActionNameCH]
       ,[ActionNameCS]
       ,[ActionNameJP]
       ,[ActionNameIT]
       ,[ActionNameTH]
       ,[ActionNameKO]
       ,[IsInternal]
       ,[ActionNameVI]
       ,[ActionNameCN])
 VALUES
       (
		5573
		,'LA_LaunchNewProductIns'
		,'Launch a new Product'
		,'Launch a new Product'
		,'Launch a new Product'
		,'Launch a new Product'
		,'Launch a new Product'
		,'Launch a new Product'
		,'Launch a new Product'
		,0
		,'Launch a new Product'
		,'Launch a new Product'
	)

