USE bodb_licensee
GO
-------********* Create Table *********------- 
--1.LA_User
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_User'))
BEGIN
DROP TABLE LA_User
END

CREATE Table LA_User
 (     
    UserID	int NOT NULL IDENTITY(1,1),
    GroupID	int NOT NULL,
    Username	varchar(50) NOT NULL,
    UserPwd	varchar(50) NOT NULL,
    DisplayName	nvarchar(100) NOT NULL,
    UserSalt	varchar(50) NOT NULL,
    StatusID	TinyINT,
    Creator	int,
    CreatedDate	datetime,
    ModifiedDate	datetime 
 )
ON OWA_data
GO
CREATE UNIQUE CLUSTERED Index CIX_LA_User ON LA_User
(UserID);

GO 
GRANT SELECT ON dbo.LA_User TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_User TO vnteam AS dbo
GO
--2 LA_UserFunction
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_UserFunction'))
BEGIN
DROP TABLE LA_UserFunction
END

CREATE Table LA_UserFunction
 (
    UserID INT NOT NULL,
    FunctionID INT NOT NULL,    
    Modifydate DATETIME,
    Modifier INT,
    StatusID TINYINT NOT NULL  
 )
ON OWA_data
GO
--DROP INDEX CIX_UserFunctionParty ON OA_UserFunctionsParty
CREATE UNIQUE CLUSTERED Index CIX_LA_UserFunction ON LA_UserFunction
(UserID,FunctionID);
GO
GRANT SELECT ON dbo.LA_UserFunction TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_UserFunction TO vnteam AS dbo
GO
--3 LA_UserParty
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_UserParty'))
BEGIN
DROP TABLE LA_UserParty
END
CREATE Table LA_UserParty
 (    
    UserID INT NOT NULL,
    PartyID INT NOT NULL,
    Modifydate DATETIME,
    Modifier INT,    
    StatusID TINYINT NOT NULL    
 )
ON OWA_data
GO
--DROP INDEX CIX_UserFunctionParty ON OA_UserFunctionsParty
CREATE UNIQUE CLUSTERED Index CIX_LA_UserParty ON LA_UserParty
(UserID,PartyID);

GO 
GRANT SELECT ON dbo.LA_UserParty TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_UserParty TO vnteam AS dbo
GO

--5 LA_Group
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_Group'))
BEGIN
DROP TABLE LA_Group
END
CREATE Table LA_Group
 (     
    GroupID INT NOT NULL IDENTITY(1,1),
    GroupName NVARCHAR(100) NOT NULL,   
    GroupDesc NVARCHAR(100),   
    StatusID INT NOT NULL,
    ModifyDate Datetime,
    Modifier	 INT    
 )
ON OWA_data
GO
CREATE UNIQUE CLUSTERED Index CIX_LA_Group ON LA_Group
(GroupID);
GO
GRANT SELECT ON dbo.LA_Group TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_Group TO vnteam AS dbo
GO

--6 LA_GroupFunction
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_GroupFunction'))
BEGIN
DROP TABLE LA_GroupFunction
END
CREATE Table LA_GroupFunction
 (     
    GroupID	int NOT NULL,
    FunctionID	int NOT NULL   
 )
ON OWA_data
GO
CREATE UNIQUE CLUSTERED Index CIX_LA_GroupFunction ON LA_GroupFunction
(GroupID,FunctionID);
GO
GRANT SELECT ON dbo.LA_GroupFunction TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_GroupFunction TO vnteam AS dbo
GO

--8.LA_Function
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_Function'))
BEGIN
DROP TABLE LA_Function
END
CREATE Table LA_Function
 (     
    FunctionID	int NOT NULL IDENTITY(1,1),
    FunctionName	nvarchar(100) NOT NULL,
    FunctionDesc	nvarchar(100),
    ParentID	int NOT NULL,
    ParentName	nvarchar(100),
    URL	varchar(100),
    CreatedDate	datetime NOT NULL,
    ModifiedDate	datetime NOT NULL,
    DisplayOrder	int,
    Creator	int,
    StatusID	Tinyint NOT NULL,
    FunctionKey	nvarchar(50)   
 )
ON OWA_data
GO
CREATE UNIQUE CLUSTERED Index CIX_LA_Function ON LA_Function
(FunctionID);
GO 
GRANT SELECT ON dbo.LA_Function TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_Function TO vnteam AS dbo
GO

--9.LA_FunctionParty
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_FunctionParty'))
BEGIN
DROP TABLE LA_FunctionParty
END
CREATE Table LA_FunctionParty
 (     
    FunctionID	int,
    PartyID	int,
   
 )
ON OWA_data
GO
CREATE UNIQUE CLUSTERED Index CIX_LA_FunctionParty ON LA_FunctionParty
(FunctionID,PartyID);
GO 
GRANT SELECT ON dbo.LA_FunctionParty TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_FunctionParty TO vnteam AS dbo
GO

--10.LA_OnUser
IF (EXISTS (SELECT 1 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_CATALOG = 'bodb_licensee' 
                 AND  TABLE_NAME = 'LA_OnUser'))
BEGIN
DROP TABLE LA_OnUser
END
CREATE Table LA_OnUser
 (     
    Custid		int,
    Reload_time	smalldatetime,
    On_userid		int not null IDENTITY(1,1),
    IP			nvarchar(100),
    iskickedout	bit,
    NetSessionID	varchar(30)
    CONSTRAINT PK_OnUserID PRIMARY KEY NONCLUSTERED (On_userid)
 )
ON OWA_data
GO

GRANT SELECT ON dbo.LA_OnUser TO bodbLicenseeNet AS dbo
GRANT SELECT ON dbo.LA_OnUser TO bodbAdminNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_OnUser TO vnteam AS dbo
GO

/*
--4 LA_UserSpecialPermission
--DROP TABLE LA_UserSpecialPermission
CREATE Table LA_UserSpecialPermission
 (     
    UserID INT NOT NULL,
    FunctionID INT NOT NULL,   
    PartyID INT NOT NULL,
    ModifyDate Datetime,
    Modifier	 INT,
    StatusID	 TINYINT
 )
ON OWA_data
GO
--DROP INDEX CIX_UserFunctionParty ON OA_UserFunctionsParty
CREATE UNIQUE CLUSTERED Index CIX_LA_UserSpecialPermission ON LA_UserSpecialPermission
(UserID,FunctionID,PartyID);
GO 
GRANT SELECT ON dbo.LA_UserSpecialPermission TO bodbLicenseeNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_UserSpecialPermission TO vnteam AS dbo
GO
--
*/

/*
--7.LA_GroupParty
--DROP TABLE LA_GroupParty
CREATE Table LA_GroupParty
 (     
    GroupID	int,
    PartyID	int  
 )
ON OWA_data
GO
CREATE UNIQUE CLUSTERED Index CIX_LA_GroupParty ON LA_GroupParty
(GroupID,PartyID);
GO
GRANT SELECT ON dbo.LA_GroupParty TO bodbLicenseeNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_GroupParty TO vnteam AS dbo
GO
*/


--Rebate Table 
/*
GO
CREATE TABLE LA_LicenseeProductRebate
(
    ID	INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
    LicenseeID		INT NOT NULL,
	ProductID		INT NOT NULL,
    FromFee			INT,
    ToFee			INT,
    Rate			Money,
    Currency		INT NOT NULL,
    FromDate		Datetime,
    ToDate			Datetime
)
ON OWA_data
GO

GRANT SELECT ON dbo.LA_LicenseeFeeRebate TO bodbLicenseeNet AS dbo
GRANT VIEW DEFINITION ON dbo.LA_LicenseeFeeRebate TO vnteam AS dbo
GO
--alter table ChargeInfo
--add column WaiveFrom
ALTER TABLE dbo.OAS_ChargeInfo
ADD WaiveFrom DATETIME NULL
--add column WaiveTo
ALTER TABLE dbo.OAS_ChargeInfo
ADD WaiveTo DATETIME NULL
*/