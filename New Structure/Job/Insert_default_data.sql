-------*****INSERT Data******-------------
--User
TRUNCATE Table LA_User
INSERT INTO LA_User (GroupID,Username,UserPwd,DisplayName,UserSalt,StatusID,Creator,CreatedDate,ModifiedDate)
SELECT 1,'User_IT','06C5CA94D7C2588B467206F20DFADDC543D54C4E','User IT','CJgH/18v96/w4YAocA==',1,1,GETDATE(),GETDATE()
UNION
SELECT 2,'User_Admin','B12A1ADC414901E19FD321EE7134B2E0EE23C53C','User Admin','+/lMlQTt+grL63qhnw==',1,1,GETDATE(),GETDATE()
UNION
SELECT 3,'User_Normal','2EFDBED0E7BA3D48A017087FEDD3A6C74D262920','User Normal','svR9T+hBYlKIs2BzkQ==',1,1,GETDATE(),GETDATE()

--Function
TRUNCATE TABLE LA_Function
INSERT INTO LA_Function (FunctionName,FunctionDesc,ParentID,ParentName,
				    URL,CreatedDate,ModifiedDate,DisplayOrder,
				    Creator,StatusID,FunctionKey)
SELECT FunctionName,FunctionDesc,ParentID,ParentName,
				    URL,CreatedDate,ModifiedDate,DisplayOrder,
				    1,IsActive,FunctionKey
FROM dbo.OA_Functions WITH (NOLOCK) 
--Group
---Insert data LA_Group
TRUNCATE Table dbo.LA_Group
INSERT INTO dbo.LA_Group (GroupName,GroupDesc,StatusID,ModifyDate,Modifier)
SELECT 'IT User','IT User',1,GETDATE(),1
UNION ALL
SELECT 'Admin User','Admin User',1,GETDATE(),1
UNION ALL
SELECT 'Nomal User','Normal User',1,GETDATE(),1
--Insert to LA_UserFunction

TRUNCATE TABLE LA_UserFunction
DECLARE @strPer Nvarchar(2000)='',@UserID INT
--User_IT
SELECT @strPer = @strPer + FunctionName + ',' FROM LA_Function WITH (NOLOCK)  where ParentID=0
SELECT @UserID = UserID FROM LA_User WITH (NOLOCK)  where Username ='User_IT'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM dbo.LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))

--User_admin
SELECT @strPer ='Administration,Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @UserID = UserID FROM LA_User where Username ='User_Admin'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM dbo.LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--User_Normal
SELECT @strPer ='Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @UserID = UserID FROM LA_User where Username ='User_Normal'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM dbo.LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))


--Insert to OA_UserParty
DELETE LA_UserParty
DECLARE @strPer Nvarchar(2000)='',@UserID INT
--User_IT
SELECT @UserID = UserID FROM LA_User where Username ='User_IT'
INSERT INTO LA_UserParty( UserID,PartyID,Modifydate,Modifier,StatusID)
SELECT @UserID,PartyID,getdate(),@UserID,1 
FROM OAS_Party WITH (NOLOCK) WHERE PartyType = 1
--Begin Group area
--LA_GroupFunction
TRUNCATE table LA_GroupFunction
DECLARE @Group INT

SELECT @strPer = @strPer + FunctionName + ',' FROM LA_Function where ParentID=0
SELECT @Group = GroupID FROM LA_Group WITH (NOLOCK)  where GroupName ='IT User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))

--Admin User
--DECLARE @strPer Nvarchar(2000),@Group INT
SELECT @strPer ='Administration,Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @Group = GroupID FROM LA_Group where GroupName ='Admin User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--Normal User
--DECLARE @strPer Nvarchar(2000),@Group INT
SELECT @strPer ='Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @Group = GroupID FROM LA_Group where GroupName ='Nomal User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--End Group area

--begin Function area
--Insert to LA_FunctionParty
TRUNCATE TABLE La_Functionparty
INSERT INTO La_Functionparty ( Functionid
                                  , Partyid )
SELECT Functionid
              , P.Partyid
      
  FROM Oa_Functionlicensees Fl INNER JOIN Oas_Party P ON Fl.Licenseeid = P.Oldrefid
                                                     AND P.Partytype = 1
GROUP BY Functionid, P.Partyid
/*
--Rebate
DECLARE @HAIFA_ID INT
SELECT @HAIFA_ID = LicenseeID FROM bodb_licensee.dbo.licensees WHERE LicenseeName = 'HAIFA'
INSERT INTO dbo.LA_LicenseeFeeRebate(LicenseeID,FromFee,ToFee,Rate,CurrencyRebate,FromDate,ToDate)
VALUES 
(@HAIFA_ID,NULL,3000000,0,13,NULL,NULL),
(@HAIFA_ID,3000001,5000000,0.05,13,NULL,NULL),
(@HAIFA_ID,5000001,8000000,0.010,13,NULL,NULL),
(@HAIFA_ID,8000001,10000000,0.14,13,NULL,NULL),
(@HAIFA_ID,10000001,12000000,0.18,13,NULL,NULL),
(@HAIFA_ID,12000001,14000000,0.22,13,NULL,NULL),
(@HAIFA_ID,14000001,16000000,0.26,13,NULL,NULL),
(@HAIFA_ID,16000001,18000000,0.30,13,NULL,NULL),
(@HAIFA_ID,18000001,20000000,0.34,13,NULL,NULL),
(@HAIFA_ID,20000001,NULL,0.40,13,NULL,NULL)

INSERT INTO dbo.LA_LicenseeFeeRebate(LicenseeID,FromFee,ToFee,Rate,CurrencyRebate,FromDate,ToDate)
VALUES 
(0,NULL,350000,0,6,NULL,NULL),
(0,350001,650000,0.05,6,NULL,NULL),
(0,650001,950000,0.010,6,NULL,NULL),
(0,950001,1250000,0.14,6,NULL,NULL),
(0,1250001,1500000,0.18,6,NULL,NULL),
(0,1500001,1750000,0.22,6,NULL,NULL),
(0,1750001,2000000,0.26,6,NULL,NULL),
(0,2000001,2250000,0.30,6,NULL,NULL),
(0,2250001,2500000,0.34,6,NULL,NULL),
(0,2500001,NULL,0.40,6,NULL,NULL)
*/