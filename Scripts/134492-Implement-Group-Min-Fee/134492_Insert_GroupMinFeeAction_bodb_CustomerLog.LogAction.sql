<<<<<<< HEAD
	/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
=======
USE [bodb_CustomerLog]
GO
>>>>>>> 80e82b05... 134492 Create script for inserting Group Min Fee log action

/*
	Created: 20200806@Mason
	DB: DBLOG.bodb_CustomerLog
	Task: Implement Group Min Fee [#134452]
	Description: Insert Group Min Fee action into DBLOG.bodb_CustomerLog.LogAction
*/
<<<<<<< HEAD
USE [bodb_CustomerLog]
GO
=======
>>>>>>> 80e82b05... 134492 Create script for inserting Group Min Fee log action

DECLARE @LA_GroupMinFeeIns_SPName VARCHAR(50) = 'LA_GroupMinFeeIns'
DECLARE @LA_GroupMinFeeUpd_SPName VARCHAR(50) = 'LA_GroupMinFeeUpd'
DECLARE @LA_GroupMinFeeDel_SPName VARCHAR(50) = 'LA_GroupMinFeeDel'

DECLARE @LA_GroupMinFeeIns_ActionName VARCHAR(50) = 'Create Group Min Fee'
DECLARE @LA_GroupMinFeeUpd_ActionName VARCHAR(50) = 'Update Group Min Fee'
DECLARE @LA_GroupMinFeeDel_ActionName VARCHAR(50) = 'Delete Group Min Fee'

DECLARE @LA_GroupMinFeeInsLogId INT = 5569
DECLARE @LA_GroupMinFeeUpdLogId INT = 5570
DECLARE @LA_GroupMinFeeDelLogId	INT	= 5571

<<<<<<< HEAD
IF NOT EXISTS (SELECT ActionID FROM dbo.LogAction WITH (NOLOCK) 
							WHERE ActionID IN (@LA_GroupMinFeeInsLogId, @LA_GroupMinFeeUpdLogId, @LA_GroupMinFeeDelLogId))
BEGIN
	INSERT INTO [dbo].[LogAction]
=======
INSERT INTO [dbo].[LogAction]
>>>>>>> 80e82b05... 134492 Create script for inserting Group Min Fee log action
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
           (@LA_GroupMinFeeInsLogId, @LA_GroupMinFeeIns_SPName, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName, 0, @LA_GroupMinFeeIns_ActionName, @LA_GroupMinFeeIns_ActionName),
		   (@LA_GroupMinFeeUpdLogId, @LA_GroupMinFeeUpd_SPName, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName, 0, @LA_GroupMinFeeUpd_ActionName, @LA_GroupMinFeeUpd_ActionName),
		   (@LA_GroupMinFeeDelLogId, @LA_GroupMinFeeDel_SPName, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName, 0, @LA_GroupMinFeeDel_ActionName, @LA_GroupMinFeeDel_ActionName)
<<<<<<< HEAD
END
=======
>>>>>>> 80e82b05... 134492 Create script for inserting Group Min Fee log action
GO