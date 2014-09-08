-------*****INSERT Data******-------------
--User
TRUNCATE Table LA_User
INSERT INTO LA_User (GroupID,Username,UserPwd,DisplayName,UserSalt,StatusID,Creator,CreatedDate,ModifiedDate)
SELECT 1,'User_IT','06C5CA94D7C2588B467206F20DFADDC543D54C4E','User IT','CJgH/18v96/w4YAocA==',1,1,GETDATE(),GETDATE()
UNION
SELECT 2,'User_Admin','B12A1ADC414901E19FD321EE7134B2E0EE23C53C','User Admin','+/lMlQTt+grL63qhnw==',1,1,GETDATE(),GETDATE()
UNION
SELECT 3,'User_Normal','2EFDBED0E7BA3D48A017087FEDD3A6C74D262920','User Normal','svR9T+hBYlKIs2BzkQ==',1,1,GETDATE(),GETDATE() >1 then 1 else GroupID END,Username,UserPwd,DisplayName,UserSalt,IsActive,Creator,CreatedDate,ModifiedDate FROM OA_Users

--Function
TRUNCATE TABLE LA_Function
INSERT INTO LA_Function (FunctionName,FunctionDesc,ParentID,ParentName,
				    URL,CreatedDate,ModifiedDate,DisplayOrder,
				    Creator,StatusID,FunctionKey)
SELECT FunctionName,FunctionDesc,ParentID,ParentName,
				    URL,CreatedDate,ModifiedDate,DisplayOrder,
				    1,IsActive,FunctionKey
FROM dbo.OA_Functions
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
SELECT @strPer = @strPer + FunctionName + ',' FROM LA_Function where ParentID=0
SELECT @UserID = UserID FROM LA_User where Username ='User_IT'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID FROM dbo.LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID FROM LA_Function
WHERE ParentID IN (SELECT FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))

--User_admin
SELECT @strPer ='Administration,Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @UserID = UserID FROM LA_User where Username ='User_Admin'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID FROM dbo.LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID FROM LA_Function
WHERE ParentID IN (SELECT FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--User_Normal
SELECT @strPer ='Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @UserID = UserID FROM LA_User where Username ='User_Normal'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID FROM dbo.LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID FROM LA_Function
WHERE ParentID IN (SELECT FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))


--Insert to OA_UserParty
DELETE LA_UserParty
--Begin Group area
--LA_GroupFunction
TRUNCATE table LA_GroupFunction
DECLARE @Group INT

SELECT @strPer = @strPer + FunctionName + ',' FROM LA_Function where ParentID=0
SELECT @Group = GroupID FROM LA_Group where GroupName ='IT User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function
WHERE ParentID IN (SELECT FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))

--Admin User
--DECLARE @strPer Nvarchar(2000),@Group INT
SELECT @strPer ='Administration,Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @Group = GroupID FROM LA_Group where GroupName ='Admin User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function
WHERE ParentID IN (SELECT FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--Normal User
--DECLARE @strPer Nvarchar(2000),@Group INT
SELECT @strPer ='Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @Group = GroupID FROM LA_Group where GroupName ='Nomal User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function
WHERE ParentID IN (SELECT FunctionID FROM LA_Function
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

