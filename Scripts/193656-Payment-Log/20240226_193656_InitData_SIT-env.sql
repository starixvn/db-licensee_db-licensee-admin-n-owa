/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231026@Danny
	DB: DBCUST.bodb_licensee
	Task: Add new Payment table RedmineId #193656
*/

USE [bodb_Licensee]

--delete from LA_Function with(rowlock) where FunctionID = 1184

truncate table OAS_Party   --del all
truncate table OAS_PartyDetail  
truncate table OAS_ChargeInfo 



GO
